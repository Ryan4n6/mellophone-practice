import AVFoundation
import Accelerate
import OSLog

/// Plays a single pitch with a brass-ish attack.
///
/// The web version builds a live sawtooth oscillator into a lowpass into a gain
/// node per note. Here each note is instead RENDERED OFFLINE into a buffer and
/// handed to a player node. Three reasons:
///
/// 1. A note is under a second and a half, so rendering it is a few tens of
///    thousands of samples and completes instantly. There is nothing to gain
///    from doing it in real time.
/// 2. The filter sweep and the envelope become plain arithmetic over a buffer,
///    which is easy to get exactly right and possible to test. Automating an
///    `AVAudioUnitEQ`'s cutoff over 150 ms is neither.
/// 3. Nothing runs on the audio render thread, so a note can never glitch the
///    metronome sharing the same engine.
final class TonePlayer {
    private let player = AVAudioPlayerNode()
    private var formatGeneration = -1
    private var format: AVAudioFormat?

    /// 0.01 to 1, matching the web version's volume slider bounds.
    var volume: Double = 0.25

    /// Play `note` for `duration` seconds. Silently does nothing if audio is
    /// unavailable; a practice tool must never trap the user in an error alert
    /// because a tone would not sound.
    func play(_ note: Note, duration: Double = 1.2) {
        play(frequency: note.frequency, duration: duration)
    }

    /// `brightnessFloor` is for the tuner's reference tone (#32), which is a
    /// SOUNDING pitch. Everything else leaves it at zero and gets the samples
    /// it always did. See `render`.
    func play(frequency: Double, duration: Double = 1.2, brightnessFloor: Double = 0) {
        guard AudioSessionController.shared.activate() else {
            Log.tone.error("[TONE] play ABORTED: audio session would not activate")
            return
        }
        do {
            let format = try AudioEngineHost.shared.start()
            if formatGeneration != AudioEngineHost.shared.formatGeneration {
                formatGeneration = AudioEngineHost.shared.formatGeneration
                self.format = format
                AudioEngineHost.shared.connect(player, format: format)
                Log.tone.info("[TONE] connected at \(format.sampleRate, privacy: .public) Hz")
            }

            guard let buffer = Self.render(frequency: frequency, duration: duration, volume: volume, format: format,
                                           brightnessFloor: brightnessFloor) else {
                Log.tone.error("[TONE] play ABORTED: could not render buffer")
                return
            }

            // Stop first so a fast tap sequence replaces the previous note
            // instead of stacking notes on top of each other. Running up a scale
            // by tapping should sound like one instrument, not a chord.
            player.stop()
            player.play()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            Log.tone.debug("[TONE] playing \(frequency, privacy: .public) Hz for \(duration, privacy: .public)s, filter held open to \(brightnessFloor, privacy: .public) Hz")
        } catch {
            Log.tone.error("[TONE] play FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        player.stop()
    }

    // MARK: - Rendering

    /// Render one note.
    ///
    /// The shape follows the web version's `playTone` so the two products sound
    /// like the same instrument: a sawtooth through a lowpass whose cutoff falls
    /// from three times the fundamental to one and a half times it over 150 ms,
    /// with an attack that overshoots and settles. That sweep is what reads as
    /// brass: the bright edge of the attack decaying into a rounder sustain.
    ///
    /// `articulation` is how a note in the middle of a PHRASE differs from a
    /// note on its own, and it defaults to "on its own", which renders exactly
    /// the samples this always has. See `Articulation`.
    ///
    /// `brightnessFloor` is the lowest the filter is allowed to close to, in
    /// Hz, and it is zero everywhere but the note check (#25) and a chart
    /// (#24). The filter
    /// follows the note, which is right for the notes this app was built on
    /// and wrong an octave under them: a euphonium's low E is 82 Hz, the
    /// filter closes to 124, and what is left is a fundamental and a second
    /// harmonic that a phone's speaker cannot make. The note would be played
    /// correctly and nobody would hear it. Holding the filter open lets the
    /// overtones through, which a small speaker CAN make and which the ear
    /// hears as the low note they belong to.
    static func render(frequency: Double, duration: Double, volume: Double, format: AVAudioFormat,
                       articulation: Articulation = .separate, brightnessFloor: Double = 0) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount

        // Band-limited sawtooth, built once into a single-cycle wavetable and
        // then read with a phase accumulator.
        //
        // Why band limited: a naive ramp, which is what a live oscillator gives
        // you, folds everything above Nyquist back down as inharmonic partials.
        // On a tool whose job is "this is what that note sounds like" those
        // aliased tones are audible and at the wrong pitches, so this is a
        // correctness problem and not a purity one. Summing only the harmonics
        // below Nyquist cannot alias at all.
        //
        // Why a table: computing the sum per sample is 64 sin() calls times
        // ~58,000 frames, tens of milliseconds of latency on every tap. Building
        // one cycle costs a fraction of that and the rest is a lookup.
        let maxHarmonic = max(1, min(64, Int(sampleRate / 2 / frequency)))

        let table = SawtoothTable.shared.table(harmonics: maxHarmonic)
        let tableSize = table.count

        // Resonant lowpass, RBJ cookbook, Q = 1 to match the web version.
        let q = 1.0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var c = BiquadCoefficients()

        // A note tongued in the middle of a line opens less bright and closes
        // down sooner than the first note of a phrase. The full sweep on every
        // note is a horn section hitting each eighth like a downbeat.
        let sweepDuration = articulation.tonguedIn ? 0.08 : 0.15
        let cutoffStart = max(brightnessFloor, frequency * (articulation.tonguedIn ? 2.2 : 3))
        let cutoffEnd = max(brightnessFloor, frequency * 1.5)
        let nyquist = sampleRate / 2
        let sweepFrames = Int(sweepDuration * sampleRate)

        var phase = 0.0
        var phaseIncrement = frequency / sampleRate
        // How long the pitch takes to arrive, in frames. Zero for a note on its
        // own, which leaves the increment alone for the whole note.
        let isSeparate = articulation == .separate
        let settleFrames = articulation.settleCents > 0 ? Int(Articulation.settleSeconds * sampleRate) : 0

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate

            // The lips find the note, they do not start on it: the pitch opens
            // a few cents under and is home inside 80 ms. Under and never over,
            // so the table chosen for the written pitch still cannot alias.
            if frame < settleFrames {
                let cents = -articulation.settleCents * exp(-t / Articulation.settleTimeConstant)
                phaseIncrement = frequency * pow(2, cents / 1200) / sampleRate
            } else if frame == settleFrames {
                phaseIncrement = frequency / sampleRate
            }

            // Linear interpolation between table points. At 2048 points per
            // cycle the error is far below the noise floor of a 16-bit output.
            let pos = phase * Double(tableSize)
            let i0 = Int(pos) % tableSize
            let i1 = (i0 + 1) % tableSize
            let frac = pos - Double(Int(pos))
            let sample = table[i0] + (table[i1] - table[i0]) * frac

            phase += phaseIncrement
            if phase >= 1 { phase -= 1 }

            // The cutoff only moves during the sweep, so the coefficients are
            // recomputed for those frames and then frozen. Recomputing them for
            // the whole note would mean two trig calls per sample for no
            // audible difference.
            if frame <= sweepFrames {
                let progress = min(1.0, t / sweepDuration)
                // Exponential fall, the curve the web version's
                // exponentialRampToValueAtTime produces.
                let cutoff = min(nyquist * 0.99, cutoffStart * pow(cutoffEnd / cutoffStart, progress))
                c = BiquadCoefficients(cutoff: cutoff, q: q, sampleRate: sampleRate)
            }

            let x0 = sample
            let y0 = c.b0 * x0 + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0

            let level = isSeparate
                ? envelope(t: t, duration: duration, volume: volume)
                : phraseEnvelope(t: t, duration: duration, volume: volume, articulation: articulation)
            channel[frame] = Float(y0 * level)
        }
        return buffer
    }

    /// The envelope of a note inside a phrase.
    ///
    /// A player does not stop the air between the notes of a line. The tongue
    /// touches each one and the sound is back within a few milliseconds. The
    /// ADSR below gives every note 100 ms of fade to silence and 40 ms of fade
    /// back in, which is right for one note played to check a pitch and is
    /// what made a real chart sound gated: at 120 an eighth note is 250 ms, so
    /// more than half of each one was fade.
    ///
    /// Two halves, and the level is the lower of them, so a note too short for
    /// both still starts and ends at zero and never clicks.
    static func phraseEnvelope(t: Double, duration: Double, volume: Double, articulation: Articulation) -> Double {
        guard t >= 0, t < duration else { return 0 }
        let sustain = volume * 0.5

        let opening: Double
        if articulation.tonguedIn {
            // The tongue: up in 10 ms to a little over the held level, back to
            // it by 70. Enough of a bump to hear two notes on one pitch as two.
            let attack = Articulation.tongueAttack, settled = 0.07
            let peak = volume * 0.62
            if t < attack {
                opening = peak * (t / attack)
            } else if t < settled {
                opening = peak + (sustain - peak) * (t - attack) / (settled - attack)
            } else {
                opening = sustain
            }
        } else {
            // The first note after a breath gets the full attack, the same one
            // a note on its own has.
            let attack = 0.04, settled = 0.12
            let peak = volume * 0.8
            if t < attack {
                opening = peak * (t / attack)
            } else if t < settled {
                opening = peak + (sustain - peak) * (t - attack) / (settled - attack)
            } else {
                opening = sustain
            }
        }

        // Into the next note: held to within 20 ms of the end, then down to
        // nothing exactly as the next note starts. Into a rest: the old 100 ms.
        let release = articulation.carriesOn ? Articulation.tongueRelease : 0.1
        let closing = sustain * min(1, (duration - t) / release)

        return min(opening, closing)
    }

    /// The web version's ADSR: up to 0.8 of volume by 40 ms, settling to 0.5 by
    /// 120 ms, held, then released over the last 100 ms. The overshoot is the
    /// point; a flat attack sounds like an organ, not a horn.
    static func envelope(t: Double, duration: Double, volume: Double) -> Double {
        let attack = 0.04, decay = 0.12, release = 0.1
        let peak = volume * 0.8, sustain = volume * 0.5
        let releaseStart = max(decay, duration - release)

        if t < attack {
            return peak * (t / attack)
        } else if t < decay {
            let progress = (t - attack) / (decay - attack)
            return peak + (sustain - peak) * progress
        } else if t < releaseStart {
            return sustain
        } else if t < duration {
            return sustain * (1 - (t - releaseStart) / (duration - releaseStart))
        }
        return 0
    }
}

/// How a note sits in the line around it.
///
/// A scale and a single tapped note are `separate`: each note is its own sound
/// with silence either side. A part is phrases, and in a phrase the notes run
/// into each other with only the tongue between them.
struct Articulation: Equatable {
    /// The note before this one ran straight into it, with no rest between.
    var tonguedIn = false
    /// This note runs straight into the next one.
    var carriesOn = false
    /// How far under the pitch the note opens, in cents. It is home within
    /// `settleSeconds`, and everything after that is exactly on the note: this
    /// app is what a student tunes their ear to, so the pitch is allowed to
    /// ARRIVE the way a player's does and never to wander once it has.
    var settleCents = 0.0

    /// What every renderer did before phrases existed, sample for sample.
    static let separate = Articulation()

    static let tongueAttack = 0.010
    static let tongueRelease = 0.020
    static let settleTimeConstant = 0.012
    /// Nearly seven time constants: 18 cents is under a fiftieth of a cent by
    /// then, so snapping to the exact pitch at this point is not a step.
    static let settleSeconds = 0.08
}

/// Normalised biquad coefficients, pulled out so the filter loop reads as the
/// difference equation it is.
struct BiquadCoefficients {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0

    init() {}

    /// Lowpass, RBJ audio cookbook.
    init(cutoff: Double, q: Double, sampleRate: Double) {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let cosW0 = cos(w0), sinW0 = sin(w0)
        let alpha = sinW0 / (2 * q)
        let a0 = 1 + alpha
        b0 = ((1 - cosW0) / 2) / a0
        b1 = (1 - cosW0) / a0
        b2 = ((1 - cosW0) / 2) / a0
        a1 = (-2 * cosW0) / a0
        a2 = (1 - alpha) / a0
    }
}

/// Cache of single-cycle band-limited sawtooth tables.
///
/// The table depends only on HOW MANY harmonics fit under Nyquist, not on the
/// pitch, so there are at most 64 distinct tables in the whole app and they can
/// all be built once. Rebuilding per note was costing about 131,000 sin() calls
/// each time, which dominated the render: a thirteen-note scale spent most of
/// its time recomputing tables it had already computed.
final class SawtoothTable {
    static let shared = SawtoothTable()

    private static let size = 2048
    private var cache: [Int: [Double]] = [:]
    private let lock = NSLock()

    private init() {}

    func table(harmonics: Int) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[harmonics] { return cached }

        // A saw is the sum of sin(n)/n. Normalise by the partial sum actually
        // used, so the peak does not depend on how many harmonics survived;
        // otherwise low notes, which fit more harmonics under Nyquist, come out
        // markedly louder than high ones.
        var norm = 0.0
        for n in 1...harmonics { norm += 1.0 / Double(n) }

        // One harmonic at a time across the whole cycle, with the sines taken
        // by vForce, where this used to be 2048 x harmonics separate calls to
        // sin(). Same sum in the same order. The reason is the debug build,
        // which is what gets installed on a phone: the first one second tone
        // rendered took 169 ms there and the second took 26, and the 143 ms
        // between them is this table. A part's opening bars need several
        // tables nobody has built yet, so the first press of Play sat silent
        // far longer than any press after it.
        var count = Int32(Self.size)
        let phases = (0..<Self.size).map { 2 * Double.pi * Double($0) / Double(Self.size) }
        var arguments = [Double](repeating: 0, count: Self.size)
        var sines = [Double](repeating: 0, count: Self.size)
        var table = [Double](repeating: 0, count: Self.size)
        for n in 1...harmonics {
            var multiple = Double(n)
            var weight = 1 / Double(n)
            vDSP_vsmulD(phases, 1, &multiple, &arguments, 1, vDSP_Length(Self.size))
            vvsin(&sines, arguments, &count)
            vDSP_vsmaD(sines, 1, &weight, table, 1, &table, 1, vDSP_Length(Self.size))
        }
        var scale = 1 / norm
        vDSP_vsmulD(table, 1, &scale, &table, 1, vDSP_Length(Self.size))
        cache[harmonics] = table
        return table
    }
}
