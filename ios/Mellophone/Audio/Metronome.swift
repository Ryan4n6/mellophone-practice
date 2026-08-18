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

    /// Downbeat haptic. FOREGROUND ONLY, and that is an iOS rule rather than a
    /// gap here: CoreHaptics will not play while the app is backgrounded or the
    /// device is locked. The click keeps going; the buzz does not. The toggle's
    /// subtitle says so, because a feature that silently stops working looks
    /// like a bug.
    ///
    /// `Haptics` also no-ops on hardware without a haptic engine rather than
    /// failing, so this is free to leave on.
    ///
    /// Historical note: this was defaulted OFF for one build to test whether
    /// CoreHaptics was killing background audio. It was not. The real cause was
    /// the engine stalling while reporting itself healthy, see
    /// `detectAndRepairStall`.
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

    /// The SHARED engine, not a private one. See AudioEngineHost for why: a
    /// second engine can force a reconfiguration that restarts this one, which
    /// would break the click the moment a student taps a note to check pitch.
    private var engine: AVAudioEngine { AudioEngineHost.shared.engine }
    private let player = AVAudioPlayerNode()
    private let haptics = Haptics()

    private var renderFormat: AVAudioFormat?
    /// Which host format generation the cached click buffers were built for.
    /// Starts at a value the host can never report so the first run always builds.
    private var formatGeneration = -1

    // MARK: - Schedule state (schedulerQueue only)

    private let schedulerQueue = DispatchQueue(label: "com.massfeller.mellophone.metronome", qos: .userInitiated)
    private var schedulerTimer: DispatchSourceTimer?

    /// Mirrors `isRunning` for the scheduler's benefit. `isRunning` is
    /// `@Published`, so it is written on the main queue; reading it from the
    /// scheduler queue would be a data race on every pump. This flag is touched
    /// only on `schedulerQueue`.
    /// Remembers that an interruption stopped a RUNNING metronome, so the end
    /// of that interruption can restart it without also starting one that the
    /// person had deliberately left stopped.
    /// How many beats are kept queued on the player. Four is enough that a
    /// scheduler wake-up can be late by three whole beats without a gap, and
    /// small enough that Stop is not audibly delayed.
    private let queueDepth = 4
    private var outstandingBuffers = 0
    /// Beats the player has finished, counted from the last re-anchor. Drives
    /// the dots.
    private var playedBeats = 0
    private var beatBuffers: [BeatBufferKey: AVAudioPCMBuffer] = [:]
    /// Player sample at which the run began, for the drift report only.
    private var anchorPlayerSample: AVAudioFramePosition?

    /// Number of scheduler wake-ups. Diagnostic only.
    ///
    /// This is the discriminator for the background failure: if the ENGINE's
    /// render clock keeps advancing while the PLAYER's does not, the audio unit
    /// is fine and our scheduler starved the buffer queue. If both freeze, iOS
    /// stopped rendering and nothing we schedule could have helped.
    private var pumpCount = 0
    /// Player sample seen at the previous diagnostic tick, to detect a stall.
    private var lastProbedPlayerSample: AVAudioFramePosition?
    /// Player sample seen at the previous pump, for the stall watchdog.
    private var lastPumpPlayerSample: AVAudioFramePosition?
    private var stalledPumps = 0
    private var wasRunningBeforeInterruption = false
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
            // Engine and player state go in every line so a background failure
            // says WHICH thing stopped: the engine, the player node, or the
            // session underneath both.
            let session = AVAudioSession.sharedInstance()
            let line = String(
                format: "[METRO-DRIFT] %@ tempo=%d beats=%d audio=%.3fs wall=%.3fs skew=%+.1fms maxScheduleErr=%.3f engine=%@ player=%@ session=%@ other=%@ route=%@ opts=%lu cat=%@ power=%@ engineClock=%@s pumps=%d sched=%d haptics=%@",
                state, self.tempo, r.beatsSounded, r.audioElapsed, r.wallElapsed,
                r.wallClockSkew * 1000, r.maxScheduleErrorSamples,
                self.engine.isRunning ? "run" : "STOPPED",
                self.player.isPlaying ? "play" : "STOPPED",
                session.isOtherAudioPlaying ? "otherAudio" : "solo",
                session.secondaryAudioShouldBeSilencedHint ? "SILENCE-HINT" : "ok",
                session.currentRoute.outputs.first?.portType.rawValue ?? "none",
                // Printed so a log can PROVE which session configuration is
                // actually running, rather than which one the source says.
                // A fix that never made it into the build reads exactly like a
                // fix that did not work.
                session.categoryOptions.rawValue,
                session.category.rawValue,
                // Low Power Mode aggressively curtails background work and is
                // an easy thing to have on without remembering. If it is set,
                // that is a different investigation entirely.
                ProcessInfo.processInfo.isLowPowerModeEnabled ? "LOW-POWER" : "normal",
                // The engine's own render clock. Advances whenever the audio
                // hardware is pulling, regardless of whether THIS player has
                // anything queued.
                self.engine.outputNode.lastRenderTime.map {
                    String(format: "%.3f", Double($0.sampleTime) / $0.sampleRate)
                } ?? "nil",
                self.pumpCount,
                self.scheduledThrough,
                self.hapticsEnabled ? "on" : "off"
            )
            print(line)
            // If the player's clock has not moved since the last check while the
            // scheduler is still active and the queue is full, rendering has
            // stopped. Probe what the system thinks is going on, and try the
            // three things that could plausibly restart it. This is a diagnostic
            // that doubles as a repair.
            if let now = self.currentPlayerSample() {
                if now == self.lastProbedPlayerSample {
                    let session = AVAudioSession.sharedInstance()
                    var results: [String] = []
                    results.append("bgTime=\(String(format: "%.0f", UIApplication.shared.backgroundTimeRemaining))")
                    results.append("engineRunning=\(self.engine.isRunning)")
                    do {
                        try session.setActive(true)
                        results.append("setActive=ok")
                    } catch {
                        results.append("setActive=FAILED(\(error.localizedDescription))")
                    }
                    if !self.engine.isRunning {
                        do { try self.engine.start(); results.append("engineStart=ok") }
                        catch { results.append("engineStart=FAILED(\(error.localizedDescription))") }
                    }
                    if !self.player.isPlaying {
                        self.player.play()
                        results.append("playerPlay=issued")
                    }
                    FileLog.write("[METRO-STALL] " + results.joined(separator: " "))

                    // Logging only. Repair belongs to `detectAndRepairStall`,
                    // which runs on the scheduler at 40 ms and reacts in half a
                    // second rather than the five seconds between these ticks.
                    // This probe originally did the repairing, which is how the
                    // cause was found; leaving both in would mean two rebuilds
                    // racing each other.
                } else {
                }
                self.lastProbedPlayerSample = now
            }
            // devicectl --console pipes stdout, so it is block buffered and a
            // line would otherwise sit unseen for minutes. Flush every time.
            fflush(stdout)
            FileLog.write(line)
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
            self?.wasRunningBeforeInterruption = self?.isRunning ?? false
            Log.metro.info("[METRO] stopping for audio interruption")
            DispatchQueue.main.async { self?.stop(reason: "interruption") }
        }
        // An interruption that ends with .shouldResume means the system is
        // handing the session back and expects playback to continue. Not
        // resuming is why any interruption used to kill the click permanently.
        AudioSessionController.shared.onInterruptionEnded = { [weak self] shouldResume in
            guard let self, shouldResume, self.wasRunningBeforeInterruption else { return }
            self.wasRunningBeforeInterruption = false
            Log.metro.info("[METRO] resuming after interruption")
            #if DEBUG
            FileLog.write("[METRO] resuming after interruption")
            #endif
            DispatchQueue.main.async { self.start() }
        }
        AudioSessionController.shared.onRouteLoss = { [weak self] in
            Log.metro.info("[METRO] stopping for route loss")
            DispatchQueue.main.async { self?.stop(reason: "routeLoss") }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: AudioEngineHost.shared.engine
        )
        #if DEBUG
        // Lifecycle markers, so a console capture shows exactly where in the
        // background transition the click died rather than only that it did.
        for name in [UIApplication.didEnterBackgroundNotification,
                     UIApplication.willEnterForegroundNotification,
                     UIApplication.willResignActiveNotification,
                     UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(logLifecycle(_:)), name: name, object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(logMediaReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil
        )
        #endif
    }

    deinit {
        schedulerTimer?.cancel()
    }

    #if DEBUG
    @objc private func logLifecycle(_ note: Notification) {
        let session = AVAudioSession.sharedInstance()
        let line = "[METRO-LIFE] \(note.name.rawValue) running=\(isRunning) engine=\(engine.isRunning) player=\(player.isPlaying) sessionOther=\(session.isOtherAudioPlaying)"
        print(line)
        fflush(stdout)
        FileLog.write(line)
    }

    @objc private func logMediaReset(_ note: Notification) {
        print("[METRO-LIFE] MEDIA SERVICES WERE RESET")
        fflush(stdout)
        FileLog.write("[METRO-LIFE] MEDIA SERVICES WERE RESET")
    }
    #endif

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
            self?.outstandingBuffers = 0
            self?.lastPumpPlayerSample = nil
            self?.stalledPumps = 0
            self?.playedBeats = 0
            self?.totalBeatsSounded = 0
            self?.anchorBeatInMeasure = 0
            self?.establishAnchor()
        }

        startSchedulerTimer()
        currentBeat = anchorBeatInMeasure
        lastReportedBeat = anchorBeatInMeasure
        #if DEBUG
        startDriftLog()
        #endif
        Log.metro.info("[METRO] started tempo=\(self.tempo, privacy: .public) beats=\(self.beatsPerMeasure, privacy: .public)")
    }

    func stop(reason: String = "user") {
        #if DEBUG
        FileLog.write("[METRO] stop(reason: \(reason)) wasRunning=\(isRunning)")
        #endif
        guard isRunning else { return }
        isRunning = false
        currentBeat = -1
        lastReportedBeat = -1

        schedulerTimer?.cancel()
        schedulerTimer = nil
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
            self?.lastPumpPlayerSample = nil
            self?.stalledPumps = 0
            self?.schedule = nil
            self?.scheduledThrough = -1
            self?.outstandingBuffers = 0
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
        let format = try AudioEngineHost.shared.start()

        // Rebuild the click buffers only when the host tells us the render
        // format actually moved, which happens on a route change (48k built-in
        // speaker to 44.1k over Bluetooth). Buffers rendered at the old rate
        // would play at the wrong pitch and, worse, the wrong length.
        if formatGeneration != AudioEngineHost.shared.formatGeneration {
            formatGeneration = AudioEngineHost.shared.formatGeneration
            renderFormat = format
            AudioEngineHost.shared.connect(player, format: format)
            Log.metro.info("[METRO] connected at \(format.sampleRate, privacy: .public) Hz")
        }
    }

    @objc private func handleEngineConfigChange() {
        Log.metro.info("[METRO] engine configuration changed")
        // Posted on an arbitrary queue; stop()/start() touch @Published state.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            // Simplest correct response: stop and start again, which rebuilds the
            // buffers at the new sample rate and re-anchors against the new clock.
            self.stop(reason: "engineConfigChange")
            self.start()
        }
    }

    /// One whole beat: an 80 ms click at the front, silence for the remainder.
    ///
    /// The buffer is a full beat long rather than just the click, because beats
    /// are scheduled end to end. Its LENGTH is what places the next beat, so the
    /// silence is not padding, it is the timing.
    ///
    /// The click itself keeps the web version's shape, a sine with an
    /// exponential decay from 0.3 to 0.001 over 80 ms, so the two products sound
    /// like each other. The 0.5 ms fade-in is not in the web version and is
    /// deliberate: starting a sine at full amplitude puts a step discontinuity
    /// into the signal, which is an audible tick on top of the intended tick.
    private static func makeBeatBuffer(frequency: Double, totalFrames: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard
            totalFrames > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        let clickDuration = 0.08
        // At 220 BPM a beat is 273 ms, so the click always fits. The guard is
        // for a future tempo range, not for today.
        let clickFrames = min(totalFrames, Int(clickDuration * sampleRate))

        let peak: Double = 0.3
        let floorLevel: Double = 0.001
        let decay = log(floorLevel / peak)
        let fadeInFrames = max(1.0, sampleRate * 0.0005)

        for frame in 0..<clickFrames {
            let t = Double(frame) / sampleRate
            let envelope = peak * exp(decay * (t / clickDuration))
            let fadeIn = min(1.0, Double(frame) / fadeInFrames)
            channel[frame] = Float(sin(2 * .pi * frequency * t) * envelope * fadeIn)
        }
        for frame in clickFrames..<totalFrames {
            channel[frame] = 0
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

    /// Establish the schedule and prime the queue. Runs on `schedulerQueue`.
    ///
    /// There is no longer an anchor on the player's timeline to establish. The
    /// schedule exists only to compute BUFFER LENGTHS; see the note on
    /// `pumpSchedule` for why absolute scheduling had to go.
    private func establishAnchor() {
        guard let sampleRate = renderFormat?.sampleRate else { return }
        let bpm = Double(tempo)
        schedule = BeatSchedule(anchorSample: 0, sampleRate: sampleRate, tempo: bpm)
        scheduledThrough = -1
        anchorWallClock = CFAbsoluteTimeGetCurrent()
        anchorPlayerSample = currentPlayerSample()

        rebuildBeatBuffers()
        publishSnapshot()
        Log.metro.info("[METRO] schedule set tempo=\(bpm, privacy: .public) beatInMeasure=\(self.anchorBeatInMeasure, privacy: .public)")
        pumpSchedule()
    }

    /// Build the four buffers the click can ever need: accent and normal, each
    /// at the short and long beat length. Runs on `schedulerQueue`.
    private func rebuildBeatBuffers() {
        guard let schedule, let format = renderFormat else { return }
        let (short, long) = schedule.bufferLengthOptions
        beatBuffers = [:]
        for accent in [true, false] {
            for length in [short, long] {
                beatBuffers[BeatBufferKey(accent: accent, length: length)] =
                    Self.makeBeatBuffer(
                        frequency: accent ? 1200 : 800,
                        totalFrames: length,
                        format: format
                    )
            }
        }
    }

    /// Watch for the engine dying while claiming to be alive, and rebuild it.
    /// Returns true if a repair was started. Runs on `schedulerQueue`.
    ///
    /// This is not defensive programming for its own sake. Measured on an
    /// iPhone 16 Pro: when the device LOCKS, the audio graph stops rendering
    /// while every indicator says it is fine. `engine.isRunning` stays true,
    /// `AVAudioSession` reports active and reactivates without error, the
    /// device's render clock keeps advancing, the player node reports playing,
    /// and its queue stays full. Only the player's own sample time gives it
    /// away by not moving. Rebuilding the graph brings the sound back, on a
    /// still-dark screen, which is how we know the system was willing to play
    /// all along.
    ///
    /// So the only trustworthy signal is whether the player's clock advances.
    /// The queue-full condition matters: if the queue were empty this would be
    /// our own fault for not feeding it, and restarting the engine would be the
    /// wrong response.
    private func detectAndRepairStall() -> Bool {
        guard outstandingBuffers >= queueDepth, let now = currentPlayerSample() else {
            stalledPumps = 0
            return false
        }
        guard let last = lastPumpPlayerSample else {
            lastPumpPlayerSample = now
            return false
        }
        guard now == last else {
            lastPumpPlayerSample = now
            stalledPumps = 0
            return false
        }

        stalledPumps += 1
        guard stalledPumps >= Self.stallPumpsBeforeRepair else { return false }

        stalledPumps = 0
        lastPumpPlayerSample = nil
        Log.metro.error("[METRO] render stalled with a full queue, rebuilding the audio graph")
        hardRecover()
        return true
    }

    /// Half a second of a motionless player clock. The clock advances every
    /// render cycle, not once per beat, so even at 40 BPM half a second of no
    /// movement is unambiguous rather than a slow tempo being mistaken for a
    /// fault.
    private static let stallPumpsBeforeRepair = 12

    /// Tear the audio graph down and build it again, continuing from the next
    /// unplayed beat. Runs on `schedulerQueue`.
    private func hardRecover() {
        guard schedulerActive else { return }
        var steps: [String] = ["wasRunning=\(engine.isRunning)"]
        player.stop()
        engine.stop()
        do {
            try AudioEngineHost.shared.start()
            steps.append("hostStart=ok")
        } catch {
            steps.append("hostStart=FAILED(\(error.localizedDescription))")
        }
        player.play()
        outstandingBuffers = 0
        lastPumpPlayerSample = nil
        stalledPumps = 0
        // Resume from where the ear left off rather than from the top.
        scheduledThrough = playedBeats - 1
        steps.append("resumeFrom=\(playedBeats)")
        pumpSchedule()
        #if DEBUG
        FileLog.write("[METRO-RECOVER] " + steps.joined(separator: " "))
        #endif
    }

    /// Keep the player's queue topped up. Runs on `schedulerQueue`.
    ///
    /// Buffers are scheduled BACK TO BACK with `at: nil`, not at absolute sample
    /// times on the player's timeline. That change is the fix for a deadlock
    /// that killed the click every time the screen went dark:
    ///
    /// The old version computed its horizon from `player.playerTime`. When the
    /// screen locks, the player node stops advancing its clock even though the
    /// engine keeps rendering. A frozen clock means a frozen horizon, so nothing
    /// new was ever scheduled, so the player had nothing to render, so its clock
    /// never advanced. Each half waited on the other for ever. Measured on
    /// device: the engine clock advanced 4.95 s per 5 s tick and the scheduler
    /// woke 125 times per tick, while the beat counter sat at 48 for a minute
    /// and a half.
    ///
    /// Back-to-back scheduling never asks what time it is. It just keeps a few
    /// beats queued, and the node consumes them in order whenever it renders. A
    /// stall becomes a pause rather than a permanent death, and the timing stays
    /// exact because the buffer lengths carry the fractional beat period (see
    /// `BeatSchedule.bufferLength(forOffset:)`).
    private func pumpSchedule() {
        pumpCount += 1
        guard schedulerActive else { return }
        guard let schedule else {
            establishAnchor()
            return
        }

        if detectAndRepairStall() { return }

        while outstandingBuffers < queueDepth {
            let offset = scheduledThrough + 1
            let beatInMeasure = (anchorBeatInMeasure + offset) % beatsPerMeasure
            let key = BeatBufferKey(
                accent: beatInMeasure == 0,
                length: schedule.bufferLength(forOffset: offset)
            )
            guard let buffer = beatBuffers[key] else {
                Log.metro.error("[METRO] no buffer for length \(key.length, privacy: .public)")
                return
            }

            outstandingBuffers += 1
            scheduledThrough = offset
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.schedulerQueue.async {
                    guard let self else { return }
                    self.outstandingBuffers -= 1
                    self.totalBeatsSounded += 1
                    self.playedBeats += 1
                    self.advanceDisplayedBeat()
                    // Top up from the completion as well as from the timer, so
                    // the queue refills the instant a beat finishes rather than
                    // waiting for the next tick.
                    self.pumpSchedule()
                }
            }
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
            self.outstandingBuffers = 0
            self.playedBeats = 0
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

    // MARK: - UI beat tracking

    /// The dots and the haptic are driven by the player consuming buffers, not
    /// by a UI timer reading a clock.
    ///
    /// The previous version sampled `player.playerTime` at 60 Hz. That clock is
    /// exactly the one that stalls when the screen goes dark, so the dots would
    /// freeze alongside the click. Counting completed beats cannot stall for a
    /// different reason than the audio itself, which is the property worth
    /// having: if the dots are moving, sound is coming out.
    private func advanceDisplayedBeat() {
        let beat = (anchorBeatInMeasure + playedBeats) % beatsPerMeasure
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            guard beat != self.lastReportedBeat else { return }
            self.lastReportedBeat = beat
            self.currentBeat = beat
            if beat == 0 && self.hapticsEnabled {
                self.haptics.downbeat()
            }
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

        let offset = max(0, totalBeatsSounded - 1)
        let audioElapsed = Double(now - (anchorPlayerSample ?? now)) / snapshot.schedule.sampleRate
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
            beatsSounded: totalBeatsSounded,
            audioElapsed: audioElapsed,
            wallElapsed: wallElapsed,
            maxScheduleErrorSamples: maxError
        )
    }
}


/// Identifies one of the four buffers the click can need: accent or normal, at
/// the short or long beat length.
struct BeatBufferKey: Hashable {
    let accent: Bool
    let length: Int
}
