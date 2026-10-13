import AVFoundation
import Combine
import OSLog

/// Hears the student's horn and says what pitch it is.
///
/// The microphone is on between `start` and `stop` and at no other time, and
/// the only caller is the note check screen, which stops it when it closes and
/// when the app leaves the foreground. Nothing that comes in is kept. Each
/// block of samples is measured, turned into one number and one small picture,
/// and overwritten by the next block a tenth of a second later. There is no
/// file, no recording and, like the rest of the app, no network.
///
/// It has its OWN engine, used for input only, and never touches the engine
/// the metronome and the players share. Asking that one for its input node
/// would mean stopping and rebuilding it under whatever is using it.
final class PitchListener: ObservableObject {

    enum State: Equatable {
        /// Not listening. The screen offers a button to start.
        case idle
        /// The system's permission question is up.
        case asking
        case listening
        /// The person said no, now or earlier. Only Settings can change it.
        case denied
        /// There is no microphone to use, or the session would not carry one.
        case unavailable
    }

    struct Reading: Equatable {
        /// Hz. Nil when nothing that is a note is coming in.
        let frequency: Double?
        /// RMS of the block, 0 to 1.
        let level: Double
        /// The wave to draw, -1 to 1. Empty when there is no pitch.
        let trace: [Float]
        /// Which block this was, counting up. It is here so that two readings
        /// are never equal: a perfectly steady note gives the same pitch and
        /// the same picture block after block, the screen counts readings to
        /// decide a note has been HELD, and SwiftUI does not report a value
        /// changing to itself. Seen in the simulator, where a steady test tone
        /// sat on "hold it steady" for ever.
        var sequence = 0
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var reading = Reading(frequency: nil, level: 0, trace: [])

    /// What the scope is drawn against. See `PitchAnalysis.trace`.
    var targetFrequency: Double {
        get { lock.withLock { target } }
        set { lock.withLock { target = newValue } }
    }

    private var engine: AVAudioEngine?
    private var observers: [NSObjectProtocol] = []
    /// Set by `start`, cleared by `stop`. The permission answer arrives later
    /// and on another thread, possibly after the screen has gone.
    private var isWanted = false
    private var lastRestart = Date.distantPast

    private let lock = NSLock()
    private var target = 440.0
    private var deafUntil = Date.distantPast

    /// Everything below is only touched on this queue.
    private let queue = DispatchQueue(label: "com.massfeller.mellophone.listen", qos: .userInitiated)
    private var ring: [Double] = []
    private var held = HeldPitch()
    private var blocks = 0

    /// The samples one measurement looks at. 85 ms at 48 kHz, which is four
    /// cycles of the lowest pitch looked for and two blocks of what the
    /// microphone hands over.
    static let window = 4096

    /// The samples the PICTURE is cut from, twice the above.
    ///
    /// Six cycles of a euphonium's low E are 3,500 samples on their own, and
    /// the scope needs a cycle of run-in and its smoothing margins on top, so
    /// one measurement window drew nothing at all for the bottom three notes
    /// of that horn (#25). The pitch is still measured on the newest `window`
    /// samples only: a longer look would make the needle slower to follow a
    /// note being bent into place.
    static let scopeWindow = 8192

    deinit {
        // Not `stop()`: that publishes, and this object is on its way out. The
        // microphone and the session are the two things that must not outlive
        // it.
        observers.forEach(NotificationCenter.default.removeObserver)
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            AudioSessionController.shared.endListening()
        }
    }

    // MARK: - On and off

    func start(target: Double) {
        targetFrequency = target
        guard state != .listening, state != .asking else { return }
        isWanted = true
        #if DEBUG
        if startPretending() { return }
        #endif

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            begin()
        case .denied:
            state = .denied
            Log.audio.error("[LISTEN] microphone permission was refused earlier, not listening")
        case .undetermined:
            state = .asking
            Log.audio.info("[LISTEN] asking for the microphone")
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    Log.audio.info("[LISTEN] microphone permission \(granted ? "granted" : "refused", privacy: .public)")
                    guard self.isWanted else { self.state = .idle; return }
                    if granted { self.begin() } else { self.state = .denied }
                }
            }
        @unknown default:
            state = .unavailable
        }
    }

    func stop() {
        isWanted = false
        #if DEBUG
        pretence?.invalidate()
        pretence = nil
        #endif
        let wasListening = engine != nil
        tearDown()
        if wasListening {
            AudioSessionController.shared.endListening()
            Log.audio.info("[LISTEN] stopped, microphone off")
            #if DEBUG
            FileLog.write("[LISTEN] stopped")
            #endif
        }
        if state == .listening || state == .asking { state = .idle }
        reading = Reading(frequency: nil, level: 0, trace: [])
    }

    /// Stop hearing for a moment, without turning anything off.
    ///
    /// For when the app itself is about to make a sound: the reference tone
    /// comes out of a speaker two centimetres from the microphone, and without
    /// this the screen would congratulate the phone for being in tune with
    /// itself.
    func cover(for seconds: Double) {
        lock.withLock { deafUntil = Date().addingTimeInterval(seconds) }
        queue.async { [weak self] in
            self?.held = HeldPitch()
            self?.ring.removeAll()
        }
        reading = Reading(frequency: nil, level: 0, trace: [])
    }

    private func begin() {
        guard AudioSessionController.shared.beginListening() else {
            state = .unavailable
            return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A tap installed with a format that has no channels or no rate does
        // not throw, it raises an Objective-C exception and takes the app
        // down. That is what a simulator with no input device hands back.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.audio.error("[LISTEN] the input has no usable format (\(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch), not listening")
            #if DEBUG
            FileLog.write("[LISTEN] FAILED: input format \(format.sampleRate) Hz \(format.channelCount) ch")
            #endif
            AudioSessionController.shared.endListening()
            state = .unavailable
            return
        }

        let rate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.take(buffer, sampleRate: rate)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Log.audio.error("[LISTEN] the input engine would not start: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            FileLog.write("[LISTEN] FAILED: engine start: \(error.localizedDescription)")
            #endif
            input.removeTap(onBus: 0)
            AudioSessionController.shared.endListening()
            state = .unavailable
            return
        }

        self.engine = engine
        observe(engine)
        state = .listening
        Log.audio.info("[LISTEN] listening at \(rate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")
        #if DEBUG
        let route = AVAudioSession.sharedInstance().currentRoute
        FileLog.write("[LISTEN] listening at \(rate) Hz, in=\(route.inputs.first?.portType.rawValue ?? "none") out=\(route.outputs.first?.portType.rawValue ?? "none")")
        #endif
    }

    private func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        queue.async { [weak self] in
            self?.ring.removeAll()
            self?.held = HeldPitch()
        }
    }

    private func observe(_ engine: AVAudioEngine) {
        let center = NotificationCenter.default
        // Headphones in or out changes the input's format under the tap. The
        // engine has already stopped itself by the time this arrives, so the
        // only thing to do is build it again on the new route.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isWanted else { return }
            // One rebuild per half second at most. If the rebuild itself is
            // what the system is objecting to, this must not become a loop.
            guard Date().timeIntervalSince(self.lastRestart) > 0.5 else {
                Log.audio.error("[LISTEN] the input changed again straight after a rebuild, giving up")
                self.tearDown()
                AudioSessionController.shared.endListening()
                self.state = .idle
                return
            }
            self.lastRestart = Date()
            Log.audio.info("[LISTEN] the input changed, rebuilding")
            #if DEBUG
            FileLog.write("[LISTEN] input configuration changed, rebuilding")
            #endif
            self.tearDown()
            self.begin()
        })
        // A phone call takes the session. Stop outright and let the student
        // press Listen when they are back, which is what the metronome does
        // for an interruption it was not told to resume from.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Log.audio.info("[LISTEN] interrupted, stopping")
            self.stop()
        })
    }

    #if DEBUG
    // MARK: - A horn that is not there

    private var pretence: Timer?

    /// `-listenFake 349.2` plays this class a steady tone at that pitch IN
    /// PLACE OF the microphone, so the screen can be looked at in the
    /// simulator, which has no horn and often no input at all. Everything
    /// after the microphone is the real thing: the same blocks, the same
    /// detector, the same picture. Debug builds only.
    private func startPretending() -> Bool {
        let hz = UserDefaults.standard.double(forKey: "listenFake")
        guard hz > 0 else { return false }
        let rate = 48_000.0
        var phase = 0.0
        state = .listening
        FileLog.write("[LISTEN] PRETENDING to hear \(hz) Hz, the microphone is not in use")
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            var block = [Double](repeating: 0, count: 4800)
            for i in 0..<block.count {
                // Eight harmonics falling off as a sawtooth's do, which is
                // nearer a horn than a sine is and is what trips a naive
                // detector into an octave error.
                var sample = 0.0
                for h in 1...8 { sample += sin(2 * Double.pi * Double(h) * phase) / Double(h) }
                block[i] = sample * 0.2
                phase += hz / rate
                if phase >= 1 { phase -= 1 }
            }
            self?.hear(block, sampleRate: rate)
        }
        RunLoop.main.add(timer, forMode: .common)
        pretence = timer
        return true
    }
    #endif

    // MARK: - Hearing

    /// Called on the tap's own thread, ten or so times a second.
    private func take(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        hear((0..<Int(buffer.frameLength)).map { Double(channel[$0]) }, sampleRate: sampleRate)
    }

    private var isCovered: Bool { lock.withLock { Date() < deafUntil } }

    private func hear(_ block: [Double], sampleRate: Double) {
        let target = targetFrequency
        guard !isCovered else { return }

        queue.async { [weak self] in
            guard let self else { return }
            self.ring.append(contentsOf: block)
            if self.ring.count > Self.scopeWindow { self.ring.removeFirst(self.ring.count - Self.scopeWindow) }
            guard self.ring.count >= Self.window else { return }

            let frame = PitchAnalysis.frame(of: Array(self.ring.suffix(Self.window)), sampleRate: sampleRate)
            let steady = self.heldPitch(of: frame)
            let trace = steady.map {
                PitchAnalysis.trace(of: self.ring, sampleRate: sampleRate, heard: $0, target: target)
            } ?? []
            self.blocks += 1
            let reading = Reading(frequency: steady, level: frame.level, trace: trace, sequence: self.blocks)

            #if DEBUG
            // Every tenth block, so a note held for three seconds leaves three
            // lines to read back off the phone and not thirty.
            if self.blocks % 10 == 0 {
                let heard = steady.map { String(format: "%.1f Hz (%+.0f cents)", $0, Pitch.cents($0, target)) } ?? "nothing"
                // The raw pitch as well, so a sound the screen was right to
                // ignore can be told from a room with nothing in it.
                let raw = frame.frequency.map { String(format: "%.1f Hz", $0) } ?? "none"
                FileLog.write(String(format: "[LISTEN] level %.4f, heard %@, raw %@, wanted %.1f Hz", frame.level, heard, raw, target))
            }
            #endif

            DispatchQueue.main.async {
                // A block that was already on its way when the screen closed,
                // or when the app started to play. The second one matters: the
                // blocks that follow it are dropped, so a late reading shown
                // here would sit on the screen for the whole of the tone,
                // being counted. A test caught it doing exactly that.
                guard self.state == .listening, !self.isCovered else { return }
                self.reading = reading
            }
        }
    }

    /// The pitch to show for this block, once it is a note being held.
    ///
    /// All of the deciding is `HeldPitch`. What is here is the record of it:
    /// one line when a note takes hold and one for each sound that had a
    /// pitch and was let go, with the reason. That second line is how a
    /// session on a real horn says whether the horn itself was ever dropped,
    /// which no test on a made tone can.
    private func heldPitch(of frame: PitchAnalysis.Frame) -> Double? {
        let before = held
        let shown = held.take(frequency: frame.frequency, level: frame.level)

        if held.outcome == .held, before.outcome != .held {
            Log.audio.debug("[LISTEN] a note took hold at \(shown ?? 0, privacy: .public) Hz, level \(frame.level, privacy: .public)")
            #if DEBUG
            FileLog.write(String(format: "[LISTEN] HELD %.1f Hz after %d readings, level %.4f", shown ?? 0, held.length, frame.level))
            #endif
        } else if before.length > 0, [.silence, .died, .moved].contains(held.outcome) {
            // The run that was there is gone. Say what it was and why.
            let why: String
            switch held.outcome {
            case .died: why = "it was dying away"
            case .moved: why = "it did not stay on one note"
            default: why = "it stopped"
            }
            let wasShown = before.length >= HeldPitch.readingsNeeded
            Log.audio.debug("[LISTEN] let go of \(before.pitch ?? 0, privacy: .public) Hz after \(before.length, privacy: .public) readings: \(why, privacy: .public)")
            #if DEBUG
            FileLog.write(String(format: "[LISTEN] %@ %.1f Hz after %d readings, level %.4f: %@",
                                 wasShown ? "LOST" : "IGNORED", before.pitch ?? 0, before.length, frame.level, why))
            #endif
        }
        return shown
    }
}
