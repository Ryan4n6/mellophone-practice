import AVFoundation
import Combine
import OSLog
import UIKit

/// Sample-accurate metronome.
///
/// The design in one sentence: **the scheduler is allowed to be sloppy, the
/// schedule is not.** A `DispatchSourceTimer` wakes up roughly every 40 ms and
/// tops the queue up so that a quarter of a second of clicks is always pending.
/// That timer can be late, jittery, or preempted and it changes nothing audible,
/// because each click carries an exact `AVAudioTime` sample position computed by
/// `BeatSchedule` and the audio hardware places it there. This is the whole
/// reason the app is not a web view: `setInterval` schedules the *sound*, so its
/// jitter is the click's jitter.
///
/// State ownership, because getting this wrong is how audio code crashes:
/// - Everything under "schedule state" is touched **only** on `schedulerQueue`.
/// - `@Published` properties are written **only** on the main queue.
/// - `clockLock` guards the one struct both sides read.
final class Metronome: ObservableObject {

    // MARK: - Published UI state

    @Published private(set) var isRunning = false

    /// Zero-based beat within the measure, or -1 when stopped. Driven off the
    /// audio clock rather than a UI timer, so the dot lights on the beat the
    /// listener actually hears instead of on an independent, drifting schedule.
    @Published private(set) var currentBeat: Int = -1

    /// 40 to 220, matching the web version's slider bounds.
    @Published var tempo: Int = 120 {
        didSet {
            let clamped = min(220, max(40, tempo))
            if clamped != tempo { tempo = clamped; return }
            guard clamped != oldValue else { return }
            Log.metro.info("[METRO] tempo -> \(clamped, privacy: .public) BPM")
            reanchorIfRunning()
        }
    }

    /// 2, 3, 4 or 6. The web version offers 2/4, 3/4, 4/4 and 6/8; all four are
    /// simply a beat count for click purposes.
    @Published var beatsPerMeasure: Int = 4 {
        didSet {
            guard beatsPerMeasure != oldValue else { return }
            Log.metro.info("[METRO] time signature -> \(self.beatsPerMeasure, privacy: .public) beats")
            reanchorIfRunning()
        }
    }

    /// Downbeat haptic. Free to leave on: `Haptics` no-ops on hardware without
    /// a haptic engine rather than failing.
    @Published var hapticsEnabled = true {
        didSet {
            // The engine is otherwise only prepared at start(), so switching this
            // on mid-run used to leave `Haptics` with a nil engine and the pulse
            // silently never fired until the metronome was stopped and started.
            guard hapticsEnabled, isRunning else { return }
            haptics.prepare()
        }
    }

    // MARK: - Engine

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let haptics = Haptics()

    private var accentBuffer: AVAudioPCMBuffer?
    private var normalBuffer: AVAudioPCMBuffer?
    private var renderFormat: AVAudioFormat?

    // MARK: - Schedule state (schedulerQueue only)

    private let schedulerQueue = DispatchQueue(label: "com.massfeller.mellophone.metronome", qos: .userInitiated)
    private var schedulerTimer: DispatchSourceTimer?

    /// Mirrors `isRunning` for the scheduler's benefit. `isRunning` is
    /// `@Published`, so it is written on the main queue; reading it from the
    /// scheduler queue would be a data race on every pump. This flag is touched
    /// only on `schedulerQueue`.
    private var schedulerActive = false
    /// Beat offsets already handed to the player, counted from the current anchor.
    private var scheduledThrough = -1
    /// Which beat of the measure the anchor itself is, so a tempo change mid-bar
    /// does not silently move the downbeat.
    private var anchorBeatInMeasure = 0
    private var schedule: BeatSchedule?

    /// How far ahead of the audio clock clicks are kept queued. Long enough that
    /// a late scheduler wake-up cannot starve the queue, short enough that a
    /// tempo change is heard within a beat or so at any usable tempo.
    private let lookahead: TimeInterval = 0.25
    private let tickInterval: TimeInterval = 0.04
    /// Delay between "start" and the first click. Covers the engine's first
    /// render cycle so beat one is never clipped.
    private let startLeadIn: TimeInterval = 0.15

    // MARK: - Shared snapshot

    private let clockLock = NSLock()
    private var clockSnapshot: ClockSnapshot?

    private struct ClockSnapshot {
        let schedule: BeatSchedule
        let anchorBeatInMeasure: Int
        let beatsPerMeasure: Int
    }

    /// Main-thread ticker that reads the audio clock and lights the right dot.
    private var uiTimer: Timer?
    private var lastReportedBeat = -1

    #if DEBUG
    /// Prints a drift line to stdout every few seconds while running, so a run
    /// on real hardware can be CAPTURED rather than read off the screen:
    ///
    ///     xcrun devicectl device process launch --console com.massfeller.mellophone
    ///
    /// It keeps ticking while the app is backgrounded and the screen is locked,
    /// which makes the log itself the evidence that the audio background mode is
    /// doing its job. If the lines stop when the screen goes off, the click died
    /// with them.
    private var driftLogTimer: Timer?
    #endif

    #if DEBUG
    private func startDriftLog() {
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, let r = self.driftReport() else { return }
            let state = UIApplication.shared.applicationState == .active ? "fg" : "BG"
            print(String(
                format: "[METRO-DRIFT] %@ tempo=%d beats=%d audio=%.3fs wall=%.3fs skew=%+.1fms maxScheduleErr=%.3f samples",
                state, self.tempo, r.beatsSounded, r.audioElapsed, r.wallElapsed,
                r.wallClockSkew * 1000, r.maxScheduleErrorSamples
            ))
            // devicectl --console pipes stdout, so it is block buffered and a
            // line would otherwise sit unseen for minutes. Flush every time.
            fflush(stdout)
        }
        RunLoop.main.add(timer, forMode: .common)
        driftLogTimer = timer
    }
    #endif

    // MARK: - Drift instrumentation

    /// Wall clock at the moment the anchor was set, so a long run can be checked
    /// against real time and not just against itself. See `driftReport`.
    private var anchorWallClock: CFAbsoluteTime = 0
    private var totalBeatsSounded = 0

    // MARK: - Init

    init() {
        // Both of these callbacks arrive on whatever queue the system chose, and
        // stop() writes @Published properties, so every one of them has to hop
        // to main first. Publishing from a background thread is a SwiftUI
        // violation that shows up as a purple runtime warning at best.
        AudioSessionController.shared.onInterruption = { [weak self] began in
            guard began else { return }
            // A phone call tears the session down under us. Stop cleanly rather
            // than leave a player node scheduled against a dead clock.
            Log.metro.info("[METRO] stopping for audio interruption")
            DispatchQueue.main.async { self?.stop() }
        }
        AudioSessionController.shared.onRouteLoss = { [weak self] in
            Log.metro.info("[METRO] stopping for route loss")
            DispatchQueue.main.async { self?.stop() }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    deinit {
        schedulerTimer?.cancel()
        uiTimer?.invalidate()
    }

    // MARK: - Transport

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }

        guard AudioSessionController.shared.activate() else {
            Log.metro.error("[METRO] start ABORTED: audio session would not activate")
            return
        }

        do {
            try prepareEngineIfNeeded()
        } catch {
            Log.metro.error("[METRO] start ABORTED: engine setup failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        if hapticsEnabled { haptics.prepare() }

        isRunning = true
        currentBeat = -1
        lastReportedBeat = -1

        player.play()

        schedulerQueue.async { [weak self] in
            self?.schedulerActive = true
            self?.totalBeatsSounded = 0
            self?.anchorBeatInMeasure = 0
            self?.establishAnchor()
        }

        startSchedulerTimer()
        startUITimer()
        #if DEBUG
        startDriftLog()
        #endif
        Log.metro.info("[METRO] started tempo=\(self.tempo, privacy: .public) beats=\(self.beatsPerMeasure, privacy: .public)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        currentBeat = -1
        lastReportedBeat = -1

        schedulerTimer?.cancel()
        schedulerTimer = nil
        uiTimer?.invalidate()
        uiTimer = nil
        #if DEBUG
        driftLogTimer?.invalidate()
        driftLogTimer = nil
        #endif

        // `stop()` on the player flushes every buffer still queued, which is
        // exactly what is wanted: up to a quarter second of future clicks must
        // not keep sounding after the button says Stop.
        player.stop()

        schedulerQueue.async { [weak self] in
            self?.schedulerActive = false
            self?.schedule = nil
            self?.scheduledThrough = -1
            self?.clockLock.lock()
            self?.clockSnapshot = nil
            self?.clockLock.unlock()
        }

        haptics.stop()
        schedulerQueue.async { [weak self] in
            guard let self else { return }
            Log.metro.info("[METRO] stopped after \(self.totalBeatsSounded, privacy: .public) beats")
        }
    }

    /// The four tempo presets from the web version.
    func applyPreset(_ bpm: Int) {
        tempo = bpm
    }

    func nudgeTempo(by delta: Int) {
        tempo = min(220, max(40, tempo + delta))
    }

    // MARK: - Engine setup

    private func prepareEngineIfNeeded() throws {
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 44_100

        // Rebuild if this is the first run or if the sample rate moved under us,
        // which happens on a route change (48k speaker to 44.1k Bluetooth).
        if renderFormat?.sampleRate != sampleRate {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                throw MetronomeError.formatUnavailable
            }
            renderFormat = format

            if player.engine == nil {
                engine.attach(player)
            } else {
                engine.disconnectNodeOutput(player)
            }
            // Mono into the main mixer; the mixer upmixes to whatever the route
            // wants, so nothing here has to know about stereo or channel counts.
            engine.connect(player, to: engine.mainMixerNode, format: format)

            accentBuffer = Self.makeClick(frequency: 1200, format: format)
            normalBuffer = Self.makeClick(frequency: 800, format: format)
            Log.metro.info("[METRO] engine formatted sampleRate=\(sampleRate, privacy: .public)")
        }

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
            Log.metro.info("[METRO] engine started")
        }
    }

    @objc private func handleEngineConfigChange() {
        Log.metro.info("[METRO] engine configuration changed")
        // Posted on an arbitrary queue; stop()/start() touch @Published state.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            // Simplest correct response: stop and start again, which rebuilds the
            // buffers at the new sample rate and re-anchors against the new clock.
            self.stop()
            self.start()
        }
    }

    /// One click: a sine at `frequency` with the same 80 ms exponential decay the
    /// web version's `tick()` uses, so the two products sound like each other.
    ///
    /// The 0.5 ms fade-in is not in the web version and is deliberate: starting a
    /// sine at full amplitude puts a step discontinuity into the signal, which is
    /// an audible tick on top of the intended tick. Half a millisecond is far too
    /// short to soften the attack a musician is listening for.
    private static func makeClick(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 0.08
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channel = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = frameCount

        let peak: Double = 0.3            // matches the web version's gain
        let floorLevel: Double = 0.001    // and its exponential ramp target
        let decay = log(floorLevel / peak)
        let fadeInFrames = max(1.0, sampleRate * 0.0005)

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope = peak * exp(decay * (t / duration))
            let fadeIn = min(1.0, Double(frame) / fadeInFrames)
            channel[frame] = Float(sin(2 * .pi * frequency * t) * envelope * fadeIn)
        }
        return buffer
    }

    // MARK: - Scheduling (schedulerQueue)

    private func startSchedulerTimer() {
        let timer = DispatchSource.makeTimerSource(queue: schedulerQueue)
        timer.schedule(deadline: .now() + tickInterval, repeating: tickInterval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.pumpSchedule() }
        schedulerTimer = timer
        timer.resume()
    }

    /// Establish (or re-establish) the anchor a little ahead of the audio clock
    /// and clear the scheduled-through cursor. Runs on `schedulerQueue`.
    private func establishAnchor() {
        guard let sampleRate = renderFormat?.sampleRate else { return }
        guard let now = currentPlayerSample() else {
            // The engine has not rendered yet, so there is no clock to anchor to.
            // The scheduler tick will call back in 40 ms and try again.
            Log.metro.debug("[METRO] anchor deferred, no render time yet")
            return
        }

        let bpm = Double(tempo)
        let anchor = now + AVAudioFramePosition(startLeadIn * sampleRate)
        schedule = BeatSchedule(anchorSample: anchor, sampleRate: sampleRate, tempo: bpm)
        scheduledThrough = -1
        anchorWallClock = CFAbsoluteTimeGetCurrent() + startLeadIn

        publishSnapshot()
        Log.metro.info("[METRO] anchored at sample=\(anchor, privacy: .public) tempo=\(bpm, privacy: .public) beatInMeasure=\(self.anchorBeatInMeasure, privacy: .public)")
        pumpSchedule()
    }

    /// Queue every beat that falls inside the lookahead window. Runs on
    /// `schedulerQueue`.
    private func pumpSchedule() {
        guard schedulerActive else { return }
        guard let schedule else {
            establishAnchor()
            return
        }
        guard let now = currentPlayerSample() else { return }

        let horizon = now + AVAudioFramePosition(lookahead * schedule.sampleRate)
        var offset = scheduledThrough + 1
        // A pathological-case guard. At 220 BPM the 0.25 s window holds one beat,
        // so this bound is unreachable in normal operation; it exists so that a
        // nonsense clock reading can never queue thousands of buffers in a loop
        // that runs on a real-time-adjacent queue.
        var queuedThisPass = 0

        while schedule.sampleTime(forOffset: offset) <= horizon, queuedThisPass < 64 {
            let beatInMeasure = (anchorBeatInMeasure + offset) % beatsPerMeasure
            guard let buffer = (beatInMeasure == 0 ? accentBuffer : normalBuffer) else { break }

            let when = AVAudioTime(sampleTime: schedule.sampleTime(forOffset: offset), atRate: schedule.sampleRate)
            player.scheduleBuffer(buffer, at: when, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.schedulerQueue.async { self?.totalBeatsSounded += 1 }
            }
            scheduledThrough = offset
            offset += 1
            queuedThisPass += 1
        }

        if queuedThisPass >= 64 {
            Log.metro.error("[METRO] scheduler hit the 64-buffer guard, clock reading suspect")
        }
    }

    /// The player node's current position on its own timeline, or nil before the
    /// first render cycle. Safe to call from any thread.
    private func currentPlayerSample() -> AVAudioFramePosition? {
        guard
            let nodeTime = player.lastRenderTime,
            let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return playerTime.sampleTime
    }

    private func reanchorIfRunning() {
        guard isRunning else { return }
        schedulerQueue.async { [weak self] in
            guard let self, self.schedulerActive else { return }
            // Carry the beat position across the change so a tempo nudge in the
            // middle of a bar does not move the downbeat to wherever the slider
            // happened to be released.
            let carried: Int
            if let schedule = self.schedule, let now = self.currentPlayerSample() {
                let elapsed = max(0, schedule.offset(atOrBefore: now) + 1)
                carried = (self.anchorBeatInMeasure + elapsed) % self.beatsPerMeasure
            } else {
                carried = 0
            }

            // Flushing and re-arming the player is what makes the change audible
            // immediately: buffers already queued at the old tempo would
            // otherwise keep sounding for up to `lookahead`.
            //
            // stop() also RESETS the player node's own sample timeline, which is
            // why the old schedule has to be thrown away here rather than left
            // in place as a fallback. Keeping it would leave an anchor measured
            // against a timeline that no longer exists, and if the first
            // establishAnchor() call lands before the node has rendered again
            // (its render time is nil until then) the next pump would happily
            // schedule against that dead anchor. Nil-ing it means the pump
            // retries the anchor instead, 40 ms later, with a live clock.
            self.player.stop()
            self.player.play()

            self.schedule = nil
            self.scheduledThrough = -1
            self.anchorBeatInMeasure = carried
            self.establishAnchor()
        }
    }

    private func publishSnapshot() {
        guard let schedule else { return }
        let snapshot = ClockSnapshot(
            schedule: schedule,
            anchorBeatInMeasure: anchorBeatInMeasure,
            beatsPerMeasure: beatsPerMeasure
        )
        clockLock.lock()
        clockSnapshot = snapshot
        clockLock.unlock()
    }

    // MARK: - UI beat tracking (main queue)

    private func startUITimer() {
        // 60 Hz. This drives only the dot and the haptic, never the sound, so
        // its jitter is cosmetic by construction.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.refreshCurrentBeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        uiTimer = timer
    }

    private func refreshCurrentBeat() {
        clockLock.lock()
        let snapshot = clockSnapshot
        clockLock.unlock()

        guard let snapshot, let now = currentPlayerSample() else { return }

        let offset = snapshot.schedule.offset(atOrBefore: now)
        guard offset >= 0 else { return }  // still inside the lead-in

        let beat = (snapshot.anchorBeatInMeasure + offset) % snapshot.beatsPerMeasure
        guard beat != lastReportedBeat else { return }
        lastReportedBeat = beat
        currentBeat = beat

        if beat == 0 && hapticsEnabled {
            haptics.downbeat()
        }
    }

    // MARK: - Drift instrumentation

    /// A snapshot of how the click is actually behaving, for the record rather
    /// than for the UI. `scheduleError` is the thing the design claims to fix,
    /// and it is bounded by half a sample by construction; `wallClockSkew` is
    /// the audio clock measured against real time, which includes the device's
    /// crystal and is therefore expected to be small but non-zero.
    struct DriftReport {
        let beatsSounded: Int
        let audioElapsed: Double
        let wallElapsed: Double
        let maxScheduleErrorSamples: Double
        var wallClockSkew: Double { audioElapsed - wallElapsed }
    }

    func driftReport() -> DriftReport? {
        clockLock.lock()
        let snapshot = clockSnapshot
        clockLock.unlock()

        guard let snapshot, let now = currentPlayerSample() else { return nil }

        let rawOffset = snapshot.schedule.offset(atOrBefore: now)
        let offset = max(0, rawOffset)
        let audioElapsed = Double(now - snapshot.schedule.anchorSample) / snapshot.schedule.sampleRate
        let wallElapsed = CFAbsoluteTimeGetCurrent() - anchorWallClock

        var maxError = 0.0
        for i in 0...offset {
            maxError = max(maxError, abs(snapshot.schedule.error(forOffset: i)))
        }

        // During the lead-in the anchor is still in the future, so rawOffset is
        // negative and nothing has sounded yet. Reporting "1 beat" there makes
        // the instrument look wrong at exactly the moment someone is checking
        // whether to trust it. Seen on a device run as "beats=1 audio=-0.150s".
        return DriftReport(
            beatsSounded: rawOffset < 0 ? 0 : offset + 1,
            audioElapsed: audioElapsed,
            wallElapsed: wallElapsed,
            maxScheduleErrorSamples: maxError
        )
    }
}

enum MetronomeError: Error {
    case formatUnavailable
}
