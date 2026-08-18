import AVFoundation
import XCTest
@testable import Mellophone

/// These tests exist to answer one question with numbers instead of confidence:
/// does the click wander over a long practice session?
///
/// They deliberately use awkward tempos and sample rates, because the failure
/// mode hides at round ones. At 44,100 Hz and 120 BPM a beat is exactly 22,050
/// samples and even a broken implementation looks perfect.
final class BeatScheduleTests: XCTestCase {

    /// Tempos chosen so the beat period is not a whole number of samples at
    /// either common hardware rate. 220 and 40 are the slider's ends.
    private let awkwardTempos: [Double] = [40, 63, 97, 113, 137, 169, 208, 220]
    private let sampleRates: [Double] = [44_100, 48_000]

    func testAnchorIsBeatZero() {
        let schedule = BeatSchedule(anchorSample: 123_456, sampleRate: 48_000, tempo: 137)
        XCTAssertEqual(schedule.sampleTime(forOffset: 0), 123_456)
        XCTAssertEqual(schedule.error(forOffset: 0), 0)
    }

    /// The core claim. Over a hundred thousand beats (about nineteen hours at
    /// 90 BPM, far longer than any practice session) no beat is ever more than
    /// half a sample from where it belongs.
    func testErrorNeverExceedsHalfASampleOverAHundredThousandBeats() {
        for rate in sampleRates {
            for tempo in awkwardTempos {
                let schedule = BeatSchedule(anchorSample: 0, sampleRate: rate, tempo: tempo)
                var worst = 0.0
                for offset in stride(from: 0, through: 100_000, by: 1) {
                    worst = max(worst, abs(schedule.error(forOffset: offset)))
                }
                XCTAssertLessThanOrEqual(
                    worst, 0.5,
                    "tempo \(tempo) at \(rate) Hz drifted \(worst) samples"
                )
            }
        }
    }

    /// Half a sample at 48 kHz is about 10 microseconds. State it in the units a
    /// musician would care about so the number means something.
    func testWorstCaseErrorInMicroseconds() {
        let rate = 48_000.0
        let schedule = BeatSchedule(anchorSample: 0, sampleRate: rate, tempo: 137)
        var worst = 0.0
        for offset in 0...100_000 {
            worst = max(worst, abs(schedule.error(forOffset: offset)))
        }
        let microseconds = worst / rate * 1_000_000
        XCTAssertLessThan(microseconds, 11)
    }

    /// The regression this design exists to prevent, demonstrated rather than
    /// asserted: an implementation that adds one period at a time accumulates
    /// error without bound, and the anchored one does not.
    func testAccumulatingSchedulerDriftsAndAnchoredOneDoesNot() {
        let rate = 44_100.0
        let tempo = 137.0
        let beats = 50_000
        let periodSamples = 60.0 / tempo * rate

        // The naive approach: integer period, added repeatedly. This is the
        // shape of a `setInterval` metronome.
        let integerPeriod = AVAudioFramePosition(periodSamples)
        var cursor: AVAudioFramePosition = 0
        for _ in 0..<beats { cursor += integerPeriod }
        let naiveErrorSeconds = abs(Double(cursor) - Double(beats) * periodSamples) / rate

        let schedule = BeatSchedule(anchorSample: 0, sampleRate: rate, tempo: tempo)
        let anchoredErrorSeconds = abs(schedule.error(forOffset: beats)) / rate

        // The naive version is off by most of a second by here.
        XCTAssertGreaterThan(naiveErrorSeconds, 0.9)
        // The anchored version is off by microseconds, and always will be.
        XCTAssertLessThan(anchoredErrorSeconds, 0.00002)
    }

    /// The beat-lookup used to light the dots has to agree with the beat times
    /// used to schedule the sound, or the display drifts against the click even
    /// though the click itself is right.
    func testOffsetLookupAgreesWithScheduledTimes() {
        let schedule = BeatSchedule(anchorSample: 10_000, sampleRate: 48_000, tempo: 113)
        for offset in 0..<2_000 {
            let exact = schedule.sampleTime(forOffset: offset)
            XCTAssertEqual(schedule.offset(atOrBefore: exact), offset, "at beat \(offset)")
            // Still the same beat a sample later, and the previous beat a sample
            // earlier. This is the boundary the dots flip on.
            XCTAssertEqual(schedule.offset(atOrBefore: exact + 1), offset)
            if offset > 0 {
                XCTAssertEqual(schedule.offset(atOrBefore: exact - 1), offset - 1)
            }
        }
    }

    func testOffsetIsNegativeBeforeTheAnchor() {
        let schedule = BeatSchedule(anchorSample: 10_000, sampleRate: 48_000, tempo: 120)
        XCTAssertLessThan(schedule.offset(atOrBefore: 9_999), 0)
    }

    func testPeriodMatchesTempo() {
        XCTAssertEqual(BeatSchedule(anchorSample: 0, sampleRate: 48_000, tempo: 120).period, 0.5, accuracy: 1e-12)
        XCTAssertEqual(BeatSchedule(anchorSample: 0, sampleRate: 48_000, tempo: 60).period, 1.0, accuracy: 1e-12)
    }
}
