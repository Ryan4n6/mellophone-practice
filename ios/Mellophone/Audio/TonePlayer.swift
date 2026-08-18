import AVFoundation
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

    func play(frequency: Double, duration: Double = 1.2) {
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

            guard let buffer = Self.render(frequency: frequency, duration: duration, volume: volume, format: format) else {
                Log.tone.error("[TONE] play ABORTED: could not render buffer")
                return
            }

            // Stop first so a fast tap sequence replaces the previous note
            // instead of stacking notes on top of each other. Running up a scale
            // by tapping should sound like one instrument, not a chord.
            player.stop()
            player.play()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            Log.tone.debug("[TONE] playing \(frequency, privacy: .public) Hz for \(duration, privacy: .public)s")
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
    static func render(frequency: Double, duration: Double, volume: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
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

        // A saw is the sum of sin(n)/n. Normalise by the partial sum actually
        // used, so the peak does not depend on how many harmonics survived;
        // otherwise low notes come out markedly louder than high ones.
        var norm = 0.0
        for n in 1...maxHarmonic { norm += 1.0 / Double(n) }

        let tableSize = 2048
        var table = [Double](repeating: 0, count: tableSize)
        for i in 0..<tableSize {
            let phase = 2 * Double.pi * Double(i) / Double(tableSize)
            var v = 0.0
            for n in 1...maxHarmonic {
                v += sin(phase * Double(n)) / Double(n)
            }
            table[i] = v / norm
        }

        // Resonant lowpass, RBJ cookbook, Q = 1 to match the web version.
        let q = 1.0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var c = BiquadCoefficients()

        let sweepDuration = 0.15
        let cutoffStart = frequency * 3
        let cutoffEnd = frequency * 1.5
        let nyquist = sampleRate / 2
        let sweepFrames = Int(sweepDuration * sampleRate)

        var phase = 0.0
        let phaseIncrement = frequency / sampleRate

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate

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

            channel[frame] = Float(y0 * envelope(t: t, duration: duration, volume: volume))
        }
        return buffer
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
