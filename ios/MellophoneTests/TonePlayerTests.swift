import AVFoundation
import XCTest
@testable import Mellophone

final class ToneEnvelopeTests: XCTestCase {

    /// The web version's shape: rise to 0.8 of volume by 40 ms, settle to 0.5 by
    /// 120 ms, hold, release over the last 100 ms. The overshoot is the part that
    /// makes it read as a horn rather than an organ, so it is pinned.
    func testEnvelopeShape() {
        let v = 1.0, d = 1.2
        XCTAssertEqual(TonePlayer.envelope(t: 0, duration: d, volume: v), 0, accuracy: 1e-9)
        XCTAssertEqual(TonePlayer.envelope(t: 0.04, duration: d, volume: v), 0.8, accuracy: 1e-6)
        XCTAssertEqual(TonePlayer.envelope(t: 0.12, duration: d, volume: v), 0.5, accuracy: 1e-6)
        XCTAssertEqual(TonePlayer.envelope(t: 0.6, duration: d, volume: v), 0.5, accuracy: 1e-9)
        XCTAssertEqual(TonePlayer.envelope(t: d, duration: d, volume: v), 0, accuracy: 1e-9)
    }

    func testEnvelopeNeverExceedsPeakAndNeverGoesNegative() {
        for volume in [0.01, 0.25, 1.0] {
            for duration in [0.3, 0.8, 1.2] {
                var t = 0.0
                while t <= duration {
                    let value = TonePlayer.envelope(t: t, duration: duration, volume: volume)
                    XCTAssertGreaterThanOrEqual(value, 0, "t=\(t) d=\(duration)")
                    XCTAssertLessThanOrEqual(value, volume * 0.8 + 1e-9, "t=\(t) d=\(duration)")
                    t += 0.001
                }
            }
        }
    }

    /// A short note must not have its release start before its decay finishes,
    /// which would make the envelope run backwards.
    func testShortNoteDoesNotInvertTheEnvelope() {
        let d = 0.15
        var previous = 0.0
        var rising = true
        var t = 0.0
        while t <= d {
            let value = TonePlayer.envelope(t: t, duration: d, volume: 1)
            XCTAssertFalse(value.isNaN, "NaN at t=\(t)")
            XCTAssertGreaterThanOrEqual(value, 0)
            if rising && value < previous { rising = false }
            previous = value
            t += 0.001
        }
    }
}

final class ToneRenderTests: XCTestCase {

    private func format(_ sampleRate: Double = 48_000) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    func testBufferHasTheRequestedLength() {
        let f = format()
        let buffer = TonePlayer.render(frequency: 440, duration: 1.0, volume: 0.5, format: f)
        XCTAssertEqual(buffer?.frameLength, AVAudioFrameCount(48_000))
    }

    /// Nothing may clip. A resonant lowpass can add gain around the cutoff, so
    /// this is a real risk rather than a formality, and clipping on a tool whose
    /// job is "this is what that note sounds like" is a correctness problem.
    func testNothingClipsAtAnyPitchOrVolume() {
        let f = format()
        for note in Note.all {
            guard let buffer = TonePlayer.render(frequency: note.frequency, duration: 0.4, volume: 1.0, format: f),
                  let data = buffer.floatChannelData?[0] else {
                return XCTFail("no buffer for \(note.name)")
            }
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) {
                XCTAssertFalse(data[i].isNaN, "NaN in \(note.name)")
                peak = max(peak, abs(data[i]))
            }
            XCTAssertLessThanOrEqual(peak, 1.0, "\(note.name) peaks at \(peak)")
            XCTAssertGreaterThan(peak, 0.01, "\(note.name) is effectively silent")
        }
    }

    /// Low notes keep more harmonics below Nyquist than high ones. Without
    /// normalising by the partial sum actually used, that alone would make the
    /// bottom of the range noticeably louder than the top.
    func testLoudnessIsComparableAcrossTheRange() {
        let f = format()
        func rms(_ frequency: Double) -> Double {
            guard let b = TonePlayer.render(frequency: frequency, duration: 0.5, volume: 0.5, format: f),
                  let d = b.floatChannelData?[0] else { return 0 }
            // Measure the sustain, past the attack and the filter sweep.
            let start = Int(0.2 * 48_000), end = Int(b.frameLength)
            var sum = 0.0
            for i in start..<end { sum += Double(d[i]) * Double(d[i]) }
            return (sum / Double(end - start)).squareRoot()
        }
        let low = rms(174.61)   // F3, bottom of the written range
        let high = rms(1046.50) // C6, top
        XCTAssertGreaterThan(low, 0)
        XCTAssertGreaterThan(high, 0)
        // Within 6 dB of each other.
        let ratio = max(low, high) / min(low, high)
        XCTAssertLessThan(ratio, 2.0, "low \(low) against high \(high)")
    }

    /// The renderer has to follow the hardware, because a route change moves the
    /// sample rate and a buffer built at the old rate plays at the wrong pitch.
    func testRendersAtWhateverSampleRateItIsGiven() {
        for rate in [44_100.0, 48_000.0] {
            let buffer = TonePlayer.render(frequency: 440, duration: 0.5, volume: 0.5, format: format(rate))
            XCTAssertEqual(buffer?.frameLength, AVAudioFrameCount(rate * 0.5), "at \(rate) Hz")
        }
    }
}
