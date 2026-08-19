import AVFoundation
import XCTest
@testable import Mellophone

/// Listens to the audio and checks it is playing the RIGHT NOTES.
///
/// Everything else in this suite tests that the sound is present and well
/// behaved: the buffer is long enough, nothing clips, every onset has energy,
/// the envelope has the right shape. Not one of them would notice if the whole
/// app played A440 nine times in a row for every scale. Loud is not correct.
///
/// Music is arithmetic, so this is checkable rather than a matter of listening.
/// A note's name fixes its frequency, twelve equal steps to the octave, and the
/// distance between two pitches in cents is 1200 * log2(a/b). So: render the
/// audio, measure the fundamental of each note, and compare. Anything that gets
/// a pitch wrong (a bad frequency in the table, an off-by-one in a scale's note
/// list, notes laid into the buffer at the wrong offsets, a transposition
/// applied where it should not be) fails here and nowhere else.
///
/// Tolerance is 15 cents throughout. A cent is a hundredth of a semitone, 15 of
/// them is well under the ~25 a decent ear hears as out of tune, and it is
/// nowhere near the 100 that would be a wrong note. The detector lands inside a
/// few cents in practice; the margin is for the measurement, not the music.
final class ScalePitchTests: XCTestCase {

    private var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    }

    private let tolerance = 15.0

    // MARK: - Calibrate the instrument first

    /// Before the detector is allowed to make claims about the app, it has to be
    /// right about signals whose pitch is known by construction.
    ///
    /// This is the test that failed first and told me the FIRST detector was
    /// broken rather than the audio: plain autocorrelation reported octaves and
    /// fifths below the truth on a synthetic sawtooth, where there is nothing to
    /// blame but the measurement.
    func testTheDetectorIsAccurateOnSignalsOfKnownPitch() {
        let rate = 48_000.0
        for frequency in [146.83, 185.0, 220.0, 349.23, 440.0, 523.25, 783.99, 1046.5] {
            for harmonics in [1, 8, 24] {
                let samples = synthesise(frequency: frequency, harmonics: harmonics, seconds: 0.2, rate: rate)
                guard let heard = Pitch.fundamental(of: samples, sampleRate: rate) else {
                    XCTFail("no pitch found for \(frequency) Hz with \(harmonics) harmonics")
                    continue
                }
                XCTAssertEqual(
                    Pitch.cents(heard, frequency), 0, accuracy: 5,
                    "\(harmonics) harmonics at \(frequency) Hz: heard \(Int(heard)) Hz"
                )
            }
        }
    }

    /// A harmonically rich tone is periodic at every MULTIPLE of its period, so
    /// a detector that takes the strongest match anywhere lands an octave or a
    /// twelfth low. Pinned explicitly because that is the failure that happened,
    /// and it looked exactly like the app playing wrong notes.
    func testTheDetectorDoesNotFallForSubharmonics() {
        let rate = 48_000.0
        for frequency in [185.0, 466.16, 932.33, 987.77] {
            let samples = synthesise(frequency: frequency, harmonics: 20, seconds: 0.2, rate: rate)
            guard let heard = Pitch.fundamental(of: samples, sampleRate: rate) else {
                XCTFail("no pitch found for \(frequency) Hz")
                continue
            }
            let error = Pitch.cents(heard, frequency)
            XCTAssertEqual(error, 0, accuracy: 5, "\(frequency) Hz heard as \(Int(heard)) Hz")
            // Said out loud: these are the specific wrong answers to never accept.
            XCTAssertGreaterThan(error, -600, "\(frequency) Hz was heard a fifth or more below")
        }
    }

    /// A band-limited sawtooth, the same shape TonePlayer builds, at a pitch this
    /// test decides rather than reads from the app.
    private func synthesise(frequency: Double, harmonics: Int, seconds: Double, rate: Double) -> [Double] {
        let count = Int(seconds * rate)
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate
            var sample = 0.0
            for h in 1...harmonics where Double(h) * frequency < rate / 2 {
                sample += sin(2 * .pi * Double(h) * frequency * t) / Double(h)
            }
            out[i] = sample
        }
        return out
    }

    // MARK: - Every note in the table

    /// The strongest claim the app makes: press C5 and hear C5.
    ///
    /// `NOTES` in index.html carries a literal frequency per row and nothing
    /// downstream ever checks it against the note's NAME. A typo there is one
    /// digit in a table of 36 and would be inaudible in review, right up until a
    /// student tunes to it.
    func testEveryNoteInTheTableSoundsAtItsOwnFrequency() {
        for note in Note.all {
            guard let buffer = TonePlayer.render(
                frequency: note.frequency, duration: 0.4, volume: 0.5, format: format
            ) else {
                XCTFail("\(note.name) did not render")
                continue
            }
            guard let heard = Pitch.fundamental(of: buffer, from: 0.10, to: 0.28) else {
                XCTFail("\(note.name) has no detectable pitch")
                continue
            }
            XCTAssertEqual(
                Pitch.cents(heard, note.frequency), 0, accuracy: tolerance,
                "\(note.name) should sound at \(note.frequency) Hz, heard \(Int(heard)) Hz"
            )
        }
    }

    /// Equal temperament, checked as arithmetic rather than assumed: every
    /// semitone in the table is 100 cents from the one below it, and an octave
    /// is exactly a doubling. This is what makes the tolerance above meaningful.
    func testTheTableIsInEqualTemperament() {
        // Dropping every flat is NOT how you get one row per pitch, which is how
        // the first version of this test failed: the table spells the black keys
        // between G and A as Ab only, so filtering out flats leaves G3 sitting
        // next to A3 and the test reported a whole tone as a broken semitone.
        // Deduplicate by FREQUENCY instead, which is the thing being tested.
        var seen = Set<Double>()
        let distinct = Note.all
            .sorted { $0.frequency < $1.frequency }
            .filter { seen.insert($0.frequency).inserted }
        XCTAssertEqual(distinct.count, 31, "F#3 to C6 is 30 semitones, so 31 distinct pitches")
        for (low, high) in zip(distinct, distinct.dropFirst()) {
            XCTAssertEqual(
                Pitch.cents(high.frequency, low.frequency), 100, accuracy: 1.0,
                "\(low.name) to \(high.name) should be one semitone"
            )
        }
        guard let c4 = Note.named("C4"), let c5 = Note.named("C5"), let c6 = Note.named("C6") else {
            return XCTFail("the octave anchors are missing from the table")
        }
        XCTAssertEqual(c5.frequency / c4.frequency, 2, accuracy: 0.001)
        XCTAssertEqual(c6.frequency / c4.frequency, 4, accuracy: 0.001)
    }

    // MARK: - Every scale

    /// Play each scale and name every note back by ear.
    ///
    /// This is the test that would have caught a scale whose notes were laid
    /// into the buffer at the wrong offsets, or listed in the wrong order, or
    /// resolved to the wrong rows. `testEveryNoteHasEnergyAtItsOnset` passes in
    /// all three of those cases.
    func testEveryScalePlaysItsOwnNotesInOrder() {
        for scale in Scale.all {
            assertScaleSoundsCorrect(scale, millisecondsPerNote: 500)
        }
    }

    /// Speed changes the note length and the spacing, so it changes where every
    /// note lands in the buffer. Presto is the tight one: notes overlap there,
    /// because a release can still be sounding when the next note starts.
    func testTheNotesStayRightAtEverySpeed() {
        guard let chromatic = Scale.all.first(where: { $0.name.hasPrefix("Chromatic") }) else {
            return XCTFail("the chromatic scale is missing")
        }
        for ms in [800, 500, 300, 180] {
            assertScaleSoundsCorrect(chromatic, millisecondsPerNote: ms)
        }
    }

    /// The lip slurs are the exercise where being wrong would teach the wrong
    /// thing hardest: every note takes the same valve combination, so the ONLY
    /// thing that changes is the pitch. If those pitches are wrong, the whole
    /// point of the exercise is wrong.
    func testTheLipSlursClimbTheHarmonicSeries() {
        for scale in Scale.all where scale.name.hasPrefix("Lip Slurs") {
            guard let held = scale.heldFingering else {
                XCTFail("\(scale.name) is a lip slur and must declare the fingering it holds")
                continue
            }
            // Every note has to be REACHABLE with the held valves, on every
            // instrument, or the exercise is impossible as written. A valve
            // combination lowers a partial by a fixed number of semitones, so
            // the test is simply: does the note plus that many semitones land on
            // one of this instrument's open partials?
            for instrument in Instrument.allCases {
                for note in scale.notes {
                    XCTAssertTrue(
                        playable(note, holding: held, on: instrument),
                        "\(scale.name): \(note.name) is not reachable on \(instrument.rawValue) holding \(held)"
                    )
                }
            }
            assertScaleSoundsCorrect(scale, millisecondsPerNote: 500)
        }
    }

    /// The chart fingering is NOT the same question as "can I play this note with
    /// these valves down". E5 is open on a mellophone, and it is also the sixth
    /// partial of the 1+2 series, which is why it appears in the 1+2 lip slur.
    private func playable(_ note: Note, holding fingering: String, on instrument: Instrument) -> Bool {
        let semitones = ["Open": 0, "2": 1, "1": 2, "1+2": 3, "2+3": 4, "1+3": 5, "1+2+3": 6]
        guard
            let drop = semitones[fingering],
            let value = Fingering.semitoneValue(of: note.name)
        else { return false }
        return instrument.openPartials.contains { Fingering.semitoneValue(of: $0) == value + drop }
    }

    // MARK: - The detector can fail

    /// A negative control, because this repo has been burned by a test that
    /// could not fail for the reason it was named after (#5, #13).
    ///
    /// Render a scale with two notes deliberately swapped and confirm the
    /// measurement notices. Without this, every assertion above could be passing
    /// on a detector that returns the expected answer no matter what it hears.
    func testASwappedNoteIsActuallyCaught() {
        guard let scale = Scale.all.first(where: { $0.name.hasPrefix("Concert Bb") }) else {
            return XCTFail("the Bb scale is missing")
        }
        var notes = scale.notes
        XCTAssertGreaterThan(notes.count, 3)
        notes.swapAt(1, 2)

        let interval = 0.5
        guard let buffer = ScalePlayer.render(
            notes: notes, interval: interval, volume: 0.5, format: format
        ) else {
            return XCTFail("the sabotaged scale did not render")
        }

        // Measured against the CORRECT order, so the swapped pair must be heard
        // as wrong, and every other note must still be heard as right.
        let expected = scale.notes
        var wrong: [Int] = []
        for index in expected.indices {
            guard let heard = pitch(of: buffer, noteIndex: index, interval: interval) else {
                return XCTFail("note \(index) of the sabotaged scale has no detectable pitch")
            }
            if abs(Pitch.cents(heard, expected[index].frequency)) > tolerance { wrong.append(index) }
        }
        XCTAssertEqual(wrong, [1, 2], "only the swapped pair should be heard as wrong")
    }

    // MARK: - Helpers

    private func assertScaleSoundsCorrect(
        _ scale: Scale, millisecondsPerNote ms: Int, file: StaticString = #filePath, line: UInt = #line
    ) {
        let interval = Double(ms) / 1000
        let notes = scale.notes
        guard let buffer = ScalePlayer.render(
            notes: notes, interval: interval, volume: 0.5, format: format
        ) else {
            return XCTFail("\(scale.name) did not render at \(ms) ms", file: file, line: line)
        }

        for (index, note) in notes.enumerated() {
            guard let heard = pitch(of: buffer, noteIndex: index, interval: interval) else {
                XCTFail("\(scale.name) note \(index) (\(note.name)) has no detectable pitch at \(ms) ms",
                        file: file, line: line)
                continue
            }
            XCTAssertEqual(
                Pitch.cents(heard, note.frequency), 0, accuracy: tolerance,
                "\(scale.name) at \(ms) ms: note \(index) should be \(note.name) "
                + "(\(Int(note.frequency)) Hz), heard \(Int(heard)) Hz",
                file: file, line: line
            )
        }
    }

    /// Listen to the middle of one note.
    ///
    /// The window deliberately misses both ends: the attack is a filter sweep
    /// with an overshoot, and the release of the PREVIOUS note can still be
    /// sounding under the start of this one at the fastest speed. The steady
    /// middle is the part that has a single well defined pitch.
    private func pitch(of buffer: AVAudioPCMBuffer, noteIndex: Int, interval: Double) -> Double? {
        let noteDuration = interval * 0.9
        let onset = Double(noteIndex) * interval
        return Pitch.fundamental(of: buffer, from: onset + noteDuration * 0.35, to: onset + noteDuration * 0.75)
    }
}

/// Pitch measurement, so a test can name the note it just heard.
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
    static func fundamental(
        of window: [Double], sampleRate rate: Double,
        lowestHz: Double = 140, highestHz: Double = 1400
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

        guard let coarseLag = yinLag(coarse, rate: coarseRate, lowestHz: lowestHz, highestHz: highestHz) else {
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
        _ x: [Double], rate: Double, lowestHz: Double, highestHz: Double
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
            guard normalised[best] < 0.5 else { return nil }
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
