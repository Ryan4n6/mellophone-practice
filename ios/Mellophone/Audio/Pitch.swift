import AVFoundation

/// Pitch measurement: name the note in a stretch of audio.
///
/// This was written for the tests, to judge the app's own audio
/// (`ScalePitchTests`), and it was calibrated there against tones of known
/// pitch before it was allowed to. It lives in the app now because the same
/// question gets asked of a student's horn through the microphone (#22), and
/// the detector that ships has to be the one that was calibrated, not a
/// second one written to look like it.
///
/// YIN (de Cheveigne and Kawahara, 2002), not plain autocorrelation. That
/// distinction was not a preference, it was forced: the first version of this
/// took the largest autocorrelation peak, and a sawtooth is periodic at every
/// MULTIPLE of its period, so the largest peak is very often at twice or three
/// times the true one. It reported Bb5 as 466 Hz and B5 as 197 Hz, failures of
/// exactly -1200 and -2786 cents. Those round numbers are the signature: a real
/// wrong note is a semitone or two out, a detector fault is a whole octave or a
/// perfect fifth below, because it locked onto a subharmonic.
///
/// YIN avoids that by looking for the FIRST lag whose difference function drops
/// below a threshold rather than the deepest one anywhere. The true period gets
/// there first; its multiples are found later and ignored.
enum Pitch {

    /// Distance between two frequencies in hundredths of a semitone. Signed:
    /// positive means `a` is sharp of `b`.
    static func cents(_ a: Double, _ b: Double) -> Double {
        1200 * log2(a / b)
    }

    static func fundamental(
        of buffer: AVAudioPCMBuffer, from start: Double, to end: Double,
        lowestHz: Double = 140, highestHz: Double = 1400
    ) -> Double? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let rate = buffer.format.sampleRate
        let first = Int(start * rate)
        let last = min(Int(end * rate), Int(buffer.frameLength))
        guard last - first > 256 else { return nil }
        var window = [Double](repeating: 0, count: last - first)
        for i in 0..<window.count { window[i] = Double(channel[first + i]) }
        return fundamental(of: window, sampleRate: rate, lowestHz: lowestHz, highestHz: highestHz)
    }

    /// Two passes, for speed and then for resolution.
    ///
    /// A debug-build test suite cannot afford the full O(window x lags) search at
    /// 48 kHz across every note of every scale at every speed: the first version
    /// took over two minutes on ONE test. So the coarse pass runs on the signal
    /// decimated to a quarter rate, which costs sixteen times less, and the fine
    /// pass then searches a handful of lags around that answer at the full rate,
    /// where one sample at C6 is worth 2% of the period and interpolation has to
    /// do the rest.
    ///
    /// `doubt` is how unsure the detector is allowed to be and still answer,
    /// on YIN's own scale: 0 is a perfectly periodic signal, 1 is noise. The
    /// tests leave it at 0.5, because they listen to audio that is known to
    /// be a note and want a number for it even when it is a poor one. A
    /// microphone in a band room is the other case: most of what it hears is
    /// NOT a note, and answering anyway would put a pitch on a chair scraping.
    static func fundamental(
        of window: [Double], sampleRate rate: Double,
        lowestHz: Double = 140, highestHz: Double = 1400, doubt: Double = 0.5
    ) -> Double? {
        let decimation = 4
        let coarseRate = rate / Double(decimation)
        var coarse = [Double](repeating: 0, count: window.count / decimation)
        guard coarse.count > 64 else { return nil }
        // Averaging rather than picking every fourth sample: a boxcar is a crude
        // lowpass, and dropping samples outright would fold the sawtooth's upper
        // harmonics back down on top of the fundamental being looked for.
        for i in 0..<coarse.count {
            var sum = 0.0
            for j in 0..<decimation { sum += window[i * decimation + j] }
            coarse[i] = sum / Double(decimation)
        }

        guard let coarseLag = yinLag(coarse, rate: coarseRate, lowestHz: lowestHz, highestHz: highestHz,
                                     doubt: doubt) else {
            return nil
        }

        // Refine at full rate, within one decimated sample either side.
        let centre = coarseLag * Double(decimation)
        let span = Double(decimation) + 2
        let low = max(2, Int(centre - span))
        let high = min(window.count / 2 - 1, Int(centre + span))
        guard high > low + 1 else { return coarseRate / coarseLag }

        var d = [Double](repeating: 0, count: high + 2)
        for lag in (low - 1)...(high + 1) where lag >= 1 && lag < window.count {
            var sum = 0.0
            for i in 0..<(window.count - lag) {
                let delta = window[i] - window[i + lag]
                sum += delta * delta
            }
            d[min(lag, d.count - 1)] = sum
        }
        var best = low
        for lag in low...high where d[lag] < d[best] { best = lag }
        return rate / interpolate(d, around: best, low: low, high: high)
    }

    /// YIN's difference function with cumulative mean normalisation, returning
    /// the first lag that clears the threshold.
    private static func yinLag(
        _ x: [Double], rate: Double, lowestHz: Double, highestHz: Double, doubt: Double
    ) -> Double? {
        let minLag = max(2, Int(rate / highestHz))
        let maxLag = min(x.count / 2 - 1, Int(rate / lowestHz))
        guard maxLag > minLag + 2 else { return nil }

        var d = [Double](repeating: 0, count: maxLag + 1)
        for lag in 1...maxLag {
            var sum = 0.0
            for i in 0..<(x.count - lag) {
                let delta = x[i] - x[i + lag]
                sum += delta * delta
            }
            d[lag] = sum
        }

        // d'(tau) = d(tau) / mean(d(1...tau)). Dividing by the running mean is
        // what stops lag 0's trivial perfect match from winning and what makes a
        // single absolute threshold work across loud and quiet notes alike.
        var normalised = [Double](repeating: 1, count: maxLag + 1)
        var running = 0.0
        for lag in 1...maxLag {
            running += d[lag]
            normalised[lag] = running > 0 ? d[lag] * Double(lag) / running : 1
        }

        // THE FIRST dip below the threshold, not the deepest. This one line is
        // the whole reason the octave errors went away.
        let threshold = 0.15
        var chosen = -1
        for lag in minLag...maxLag where normalised[lag] < threshold {
            // Walk to the bottom of this dip rather than stopping on its edge.
            var here = lag
            while here + 1 <= maxLag, normalised[here + 1] < normalised[here] { here += 1 }
            chosen = here
            break
        }
        if chosen < 0 {
            // Nothing clears the threshold: take the best available and let the
            // caller's tolerance decide whether it is good enough.
            var best = minLag
            for lag in minLag...maxLag where normalised[lag] < normalised[best] { best = lag }
            guard normalised[best] < doubt else { return nil }
            chosen = best
        }
        return interpolate(normalised, around: chosen, low: minLag, high: maxLag)
    }

    /// A parabola through the minimum and its neighbours. The true period almost
    /// never lands on a whole sample, and at the top of the range the fraction is
    /// worth more than the tolerance being tested against.
    private static func interpolate(_ values: [Double], around index: Int, low: Int, high: Int) -> Double {
        guard index > low, index < high, index + 1 < values.count else { return Double(index) }
        let left = values[index - 1], centre = values[index], right = values[index + 1]
        let denominator = 2 * (2 * centre - left - right)
        guard denominator != 0 else { return Double(index) }
        let shift = (right - left) / denominator
        guard abs(shift) <= 1 else { return Double(index) }
        return Double(index) + shift
    }
}
