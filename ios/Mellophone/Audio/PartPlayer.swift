import AVFoundation
import Combine
import OSLog

/// The room a part is heard in.
///
/// A sawtooth with nothing around it, out of a phone speaker, is as harsh as a
/// sound gets, and it is not what a horn sounds like to the person playing one:
/// they hear it come back off a band room. Three choices and not a dial,
/// because the question a student has is "does it sound like a room", not
/// "what is the wet/dry mix".
enum PartRoom: String, CaseIterable, Identifiable {
    case dry, room, hall

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dry: return "Dry"
        case .room: return "Room"
        case .hall: return "Hall"
        }
    }

    var preset: AVAudioUnitReverbPreset? {
        switch self {
        case .dry: return nil
        case .room: return .mediumRoom
        case .hall: return .largeHall
        }
    }

    /// Percent wet. Low on purpose: the reverb is there to put air round the
    /// notes, and past about a third the runs smear and the rhythm a student is
    /// trying to learn gets harder to hear, not easier.
    var wet: Float {
        switch self {
        case .dry: return 0
        case .room: return 18
        case .hall: return 30
        }
    }
}

/// Plays an imported part: a count-in, then the bars, a few at a time.
///
/// `ScalePlayer` renders a whole scale into one buffer, which is right for ten
/// seconds of audio and wrong for ten minutes of it. This renders a few bars at
/// a time and queues them back to back with `at: nil`, so each buffer's LENGTH
/// is what places the next one. That is the metronome's discipline and it is
/// here for the metronome's reason: nothing is ever scheduled against the
/// player's clock, so a clock that stalls cannot stop the music being queued.
///
/// The clock is read for one thing only, the highlight, and the highlight is
/// allowed to be wrong without the sound caring.
///
/// MAKE ONE AND KEEP IT. Each instance attaches a node to the engine the whole
/// app shares, and that node is never detached, on purpose. Detaching it was
/// tried, so that a player per opened chart would not pile nodes up: taking a
/// node off the RUNNING engine left the next player's node outside the output
/// chain, and AVFoundation raised on its first `play()`, for every player from
/// then on. `PartPlayerTests` recorded that off the real engine. So the charts
/// card owns one player for as long as the tab lives, the way the Scales tab
/// owns its `ScalePlayer`, and hands it to whichever chart is open.
final class PartPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    /// The slot of `PartTimeline` currently sounding. Nil when stopped and
    /// during the count-in.
    @Published private(set) var currentSlot: Int?
    @Published private(set) var currentMeasure: Int?
    /// The beat of the current bar, from 1. What the screen counts out loud
    /// through a rest, when nothing else on it is moving.
    @Published private(set) var currentBeat: Int?
    /// 1 on the first click of the count-in, nil once the part has started.
    @Published private(set) var countInBeat: Int?

    private let player = AVAudioPlayerNode()
    private let reverb = AVAudioUnitReverb()
    /// The space the part is heard in. Dry until someone says otherwise, so a
    /// player made by a test puts out exactly what was rendered.
    var room: PartRoom = .dry {
        didSet { if room != oldValue { applyRoom() } }
    }
    private var formatGeneration = -1
    private var uiTimer: Timer?
    private var session: Session?
    private var configObserver: NSObjectProtocol?

    /// Rendering the bars after the first two happens here, off the main
    /// thread, while the bars before them are still sounding.
    private let renderQueue = DispatchQueue(label: "com.massfeller.mellophone.part", qos: .userInitiated)

    /// One press of Play. Everything a late callback needs is in here, so a
    /// buffer finishing after Stop has nothing of the NEXT run to touch.
    private final class Session {
        let timeline: PartTimeline
        let chunks: [PartTimeline.Chunk]
        let format: AVAudioFormat
        let volume: Double
        let loop: Bool
        let countInFrames: Int
        let partFrames: Int
        /// Only touched on the render queue.
        var next = 0

        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }

        init(timeline: PartTimeline, chunks: [PartTimeline.Chunk], format: AVAudioFormat,
             volume: Double, loop: Bool, countInFrames: Int) {
            self.timeline = timeline
            self.chunks = chunks
            self.format = format
            self.volume = volume
            self.loop = loop
            self.countInFrames = countInFrames
            self.partFrames = chunks.reduce(0) { $0 + $1.frames }
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    func play(_ timeline: PartTimeline, countIn: Bool, loop: Bool, volume: Double) {
        stop()
        #if DEBUG
        let pressed = Date()
        #endif

        guard AudioSessionController.shared.activate() else {
            Log.tone.error("[PART] play ABORTED: audio session would not activate")
            #if DEBUG
            FileLog.write("[PART] ABORTED: audio session would not activate")
            #endif
            return
        }

        do {
            let format = try connectedFormat()
            #if DEBUG
            let engineUp = Date()
            #endif

            let chunks = timeline.chunks(sampleRate: format.sampleRate)
            guard !chunks.isEmpty else {
                Log.tone.error("[PART] play ABORTED: the range holds no bars to play")
                #if DEBUG
                FileLog.write("[PART] ABORTED: the range holds no bars to play")
                #endif
                return
            }

            let clicks = countIn ? Self.countIn(for: timeline, format: format) : []
            let session = Session(timeline: timeline, chunks: chunks, format: format,
                                  volume: volume, loop: loop,
                                  countInFrames: clicks.reduce(0) { $0 + Int($1.frameLength) })
            self.session = session

            // SCHEDULE FIRST, then play, and never consult the clock to do it.
            // See the long note in ScalePlayer.play: a guard on the render time
            // there kept the Scales tab silent from the day it shipped.
            for click in clicks {
                player.scheduleBuffer(click, at: nil, options: [], completionHandler: nil)
            }
            // Two chunks in hand before the first sample sounds, so there is
            // always a whole chunk queued behind the one playing while the next
            // is being rendered. One in hand would leave a hole at every seam.
            //
            // On the render queue even though this waits for it, because that
            // queue is the only thing that ever advances `session.next`.
            renderQueue.sync {
                scheduleNext(session)
                scheduleNext(session)
            }
            player.play()

            isPlaying = true
            countInBeat = clicks.isEmpty ? nil : 1
            currentSlot = clicks.isEmpty ? 0 : nil
            currentMeasure = timeline.measures.first?.number
            currentBeat = nil
            startUITimer(for: session)

            let bars = timeline.measures.count
            Log.tone.info("[PART] playing \(bars, privacy: .public) bars in \(chunks.count, privacy: .public) chunks, \(timeline.duration, privacy: .public) s, count-in \(clicks.count, privacy: .public), loop \(loop, privacy: .public), pitch \(timeline.instrument?.rawValue ?? "as written", privacy: .public)")
            #if DEBUG
            // How long Play took to make a sound is logged because it is the
            // one number here a student feels, and a cold engine and a slow
            // render look identical from the outside.
            // Split in two because the halves have different cures: the engine
            // is slow once, cold, and nothing here can change that, while the
            // render is slow every time and is this file's to fix.
            let engineMs = Int(engineUp.timeIntervalSince(pressed) * 1000)
            let renderMs = Int(Date().timeIntervalSince(engineUp) * 1000)
            FileLog.write("[PART] scheduled \(bars) bars in \(chunks.count) chunks, \(timeline.duration) s, count-in \(clicks.count), loop \(loop), pitch \(timeline.instrument?.rawValue ?? "as written"), engine \(engineMs) ms, first bars \(renderMs) ms, engineRunning=\(AudioEngineHost.shared.engine.isRunning)")
            #endif
        } catch {
            Log.tone.error("[PART] play FAILED: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            FileLog.write("[PART] FAILED: \(error.localizedDescription)")
            #endif
        }
    }

    /// One note, alone: the one a student tapped to check.
    ///
    /// Through this player and not a `TonePlayer` of the screen's own, for two
    /// reasons. It comes out of the same room as the part, so the note sounds
    /// like the one they just heard go by. And it is the same node, so a tap
    /// in the middle of a run cannot leave the run sounding underneath it.
    ///
    /// `isPlaying` stays false. Nothing is being followed, and Play has to
    /// stay live so the next thing a thumb does can be to start the passage.
    ///
    /// `brightnessFloor` is for the note check, which plays what the horn
    /// SOUNDS and so goes an octave under anything else here. See
    /// `TonePlayer.render`.
    func sound(frequency: Double, duration: Double = 1.2, volume: Double, brightnessFloor: Double = 0) {
        stop()
        guard AudioSessionController.shared.activate() else {
            Log.tone.error("[PART] note ABORTED: audio session would not activate")
            return
        }
        do {
            let format = try connectedFormat()
            guard let buffer = TonePlayer.render(frequency: frequency, duration: duration,
                                                 volume: volume, format: format,
                                                 brightnessFloor: brightnessFloor) else {
                Log.tone.error("[PART] note ABORTED: \(frequency, privacy: .public) Hz would not render")
                return
            }
            // Scheduled first and then played, like a run. See `play`.
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
            Log.tone.info("[PART] one note, \(frequency, privacy: .public) Hz for \(duration, privacy: .public) s, filter held open to \(brightnessFloor, privacy: .public) Hz")
        } catch {
            Log.tone.error("[PART] note FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The engine up, and this player wired into it at the format it is
    /// running at now.
    private func connectedFormat() throws -> AVAudioFormat {
        let format = try AudioEngineHost.shared.start()
        if formatGeneration != AudioEngineHost.shared.formatGeneration {
            formatGeneration = AudioEngineHost.shared.formatGeneration
            AudioEngineHost.shared.connect(player, through: reverb, format: format)
            applyRoom()
        }
        observeConfigurationChanges()
        return format
    }

    func stop() {
        uiTimer?.invalidate()
        uiTimer = nil
        if let session {
            session.cancel()
            // Wait out a render that is already under way. Without this it can
            // finish AFTER the flush below and queue its buffer onto a stopped
            // player, where it sits until the next Play and sounds in front of
            // the count-in.
            renderQueue.sync {}
            Log.tone.debug("[PART] stopped")
        }
        session = nil
        player.stop()
        isPlaying = false
        currentSlot = nil
        currentMeasure = nil
        currentBeat = nil
        countInBeat = nil
    }

    private func finish(_ finished: Session) {
        // A buffer from a run that was already replaced has nothing to say
        // about the one playing now.
        guard session === finished else { return }
        uiTimer?.invalidate()
        uiTimer = nil
        session = nil
        isPlaying = false
        currentSlot = nil
        currentMeasure = nil
        currentBeat = nil
        countInBeat = nil
        Log.tone.info("[PART] finished")
        #if DEBUG
        FileLog.write("[PART] finished")
        #endif
    }

    // MARK: - Scheduling

    /// Render the next chunk and queue it behind whatever is already queued.
    ///
    /// Called twice up front from `play`, then once from each buffer's own
    /// completion, so the queue stays two deep without a timer deciding when.
    private func scheduleNext(_ session: Session) {
        guard !session.isCancelled else { return }
        var index = session.next
        if index >= session.chunks.count {
            guard session.loop else { return }
            index = 0
        }
        let chunk = session.chunks[index]
        guard let buffer = Self.render(chunk, volume: session.volume, format: session.format) else {
            Log.tone.error("[PART] chunk \(index, privacy: .public) would not render, stopping")
            #if DEBUG
            FileLog.write("[PART] chunk \(index) would not render, stopping")
            #endif
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session === session else { return }
                self.stop()
            }
            return
        }
        session.next = index + 1

        let isFinal = !session.loop && index == session.chunks.count - 1
        // The last buffer reports when it has been HEARD, so Stop does not
        // light up while the final note is still in the air. Every other one
        // reports as soon as the player has taken it, which is the moment to
        // start on the one after next.
        player.scheduleBuffer(buffer, at: nil, options: [],
                              completionCallbackType: isFinal ? .dataPlayedBack : .dataConsumed) { [weak self] _ in
            if isFinal {
                DispatchQueue.main.async { self?.finish(session) }
            } else {
                self?.renderQueue.async { self?.scheduleNext(session) }
            }
        }
    }

    static func render(_ chunk: PartTimeline.Chunk, volume: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        ToneSequence.render(events: chunk.events, volume: volume, format: format,
                            frames: AVAudioFrameCount(chunk.frames))
    }

    /// One bar of clicks at the tempo the part is about to be played at.
    ///
    /// The metronome's own click, high on the first beat, so it sounds like the
    /// thing the student already practises against. Each buffer is one whole
    /// beat long and the beats are cut from their own positions, the same way
    /// the chunks are, so the count-in leads into the first bar exactly on the
    /// beat it has been counting.
    static func countIn(for timeline: PartTimeline, format: AVAudioFormat) -> [AVAudioPCMBuffer] {
        let rate = format.sampleRate
        func frame(_ beat: Int) -> Int { Int((Double(beat) * timeline.secondsPerPulse * rate).rounded()) }
        return (0..<timeline.countInBeats).compactMap { beat in
            Metronome.makeBeatBuffer(frequency: beat == 0 ? 1200 : 800,
                                     totalFrames: frame(beat + 1) - frame(beat),
                                     format: format)
        }
    }

    // MARK: - Following along

    /// Drives the highlight off the audio clock, for the same reason the
    /// metronome's dots are: a separate timer would drift against the sound it
    /// is pointing at, and over a four page chart it would drift a long way.
    private func startUITimer(for session: Session) {
        let rate = session.format.sampleRate
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard
                let self, self.session === session,
                let nodeTime = self.player.lastRenderTime,
                let playerTime = self.player.playerTime(forNodeTime: nodeTime)
            else { return }

            // The player's own timeline starts at zero when it is told to play,
            // and the first buffer was queued before that, so a sample time IS
            // the distance into this run.
            let elapsed = Int(playerTime.sampleTime)
            guard elapsed >= 0 else { return }

            if elapsed < session.countInFrames {
                let beat = Int(Double(elapsed) / (session.timeline.secondsPerPulse * rate)) + 1
                let clamped = min(beat, session.timeline.countInBeats)
                if self.countInBeat != clamped { self.countInBeat = clamped }
                return
            }

            var position = elapsed - session.countInFrames
            if session.loop, session.partFrames > 0 { position %= session.partFrames }
            let seconds = Double(position) / rate
            let slot = session.timeline.slot(at: seconds)
            let measure = session.timeline.measure(at: seconds)
            if self.countInBeat != nil { self.countInBeat = nil }
            if self.currentSlot != slot, slot != nil { self.currentSlot = slot }
            if self.currentMeasure != measure, measure != nil { self.currentMeasure = measure }
            let beat = session.timeline.beat(at: seconds)
            if self.currentBeat != beat, beat != nil { self.currentBeat = beat }
        }
        RunLoop.main.add(timer, forMode: .common)
        uiTimer = timer
    }

    /// Unplugging headphones stops the engine and leaves this player silent
    /// with every flag still saying it is playing. Stopping outright is the
    /// honest answer: the student presses Play again and it starts on the new
    /// route, instead of watching a highlight that is not moving.
    /// Live, with no need to stop: the reverb is a node the sound passes
    /// through, not something baked into the buffers.
    private func applyRoom() {
        if let preset = room.preset {
            reverb.loadFactoryPreset(preset)
            reverb.wetDryMix = room.wet
            reverb.bypass = false
        } else {
            // Bypassed and not just turned to zero, so "Dry" is the rendered
            // samples and nothing else. The test that compares the engine's
            // output with what was rendered depends on that.
            reverb.wetDryMix = 0
            reverb.bypass = true
        }
        Log.tone.info("[PART] room \(self.room.rawValue, privacy: .public)")
    }

    private func observeConfigurationChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: AudioEngineHost.shared.engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            Log.tone.info("[PART] audio route changed while playing, stopping")
            #if DEBUG
            FileLog.write("[PART] audio route changed while playing, stopping")
            #endif
            self.stop()
        }
    }
}
