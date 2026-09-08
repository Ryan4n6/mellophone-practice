import XCTest
import AVFoundation
@testable import Mellophone

/// The renderer moved out of `ScalePlayer` so an imported part with uneven
/// durations and rests in it can use it. `ScalePlayerTests` and
/// `ScalePitchTests` are the regression guard on the move; these tests cover
/// only what is new, which is that onset and duration are now per event.
final class ToneSequenceTests: XCTestCase {

    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    private func twoEventsWithAGap() -> [ToneSequence.Event] {
        [ToneSequence.Event(frequency: 440, onset: 0, duration: 0.5),
         ToneSequence.Event(frequency: 440, onset: 2.0, duration: 1.0)]
    }

    func testBufferIsLongEnoughForTheLastEventToRingOut() throws {
        let buffer = try XCTUnwrap(ToneSequence.render(events: twoEventsWithAGap(),
                                                       volume: 0.25, format: format))
        XCTAssertEqual(Double(buffer.frameLength) / 48_000, 3.0, accuracy: 0.01)
    }

    /// Silence where a rest is. The gap between the two events above must be
    /// actually silent, or a rest sounds like a held note, and "how long do I
    /// sit out before I come in" is half of what an imported part is for.
    func testGapsBetweenEventsAreSilent() throws {
        let buffer = try XCTUnwrap(ToneSequence.render(events: twoEventsWithAGap(),
                                                       volume: 0.25, format: format))
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        // 1.0s to 1.9s falls entirely in the gap.
        for i in 48_000..<91_200 {
            XCTAssertEqual(data[i], 0, accuracy: 0.0001, "sample \(i) should be silent")
        }
    }

    /// Overlapping releases are summed, then the whole buffer is scaled back if
    /// the sum clipped. Clipping a run is far more audible than it being
    /// slightly quieter, which is why `ScalePlayer` did this and why it survives
    /// the move.
    func testOverlappingEventsDoNotClip() throws {
        let events = (0..<8).map {
            ToneSequence.Event(frequency: 440, onset: Double($0) * 0.02, duration: 1.0)
        }
        let buffer = try XCTUnwrap(ToneSequence.render(events: events, volume: 1.0, format: format))
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
        XCTAssertLessThanOrEqual(peak, 1.0)
        XCTAssertGreaterThan(peak, 0.1, "something has to be audible, or the test proves nothing")
    }

    /// The buffer is sized from the LATEST end, not from the last event in the
    /// list. A chord is written lowest voice last, and a long note can start
    /// before a short one that finishes later; sizing off the tail would cut it.
    func testBufferIsSizedFromTheLatestEndingEventNotTheLastOne() throws {
        let events = [ToneSequence.Event(frequency: 440, onset: 0, duration: 4.0),
                      ToneSequence.Event(frequency: 660, onset: 0.5, duration: 0.5)]
        let buffer = try XCTUnwrap(ToneSequence.render(events: events, volume: 0.25, format: format))
        XCTAssertEqual(Double(buffer.frameLength) / 48_000, 4.0, accuracy: 0.01)
    }

    /// A rest arrives as an event with no pitch, and it must occupy its time
    /// without trying to render a 0 Hz tone.
    func testAZeroFrequencyEventOccupiesTimeWithoutSounding() throws {
        let events = [ToneSequence.Event(frequency: 0, onset: 0, duration: 1.0),
                      ToneSequence.Event(frequency: 440, onset: 1.0, duration: 0.5)]
        let buffer = try XCTUnwrap(ToneSequence.render(events: events, volume: 0.25, format: format))
        XCTAssertEqual(Double(buffer.frameLength) / 48_000, 1.5, accuracy: 0.01)
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        for i in 0..<47_000 {
            XCTAssertEqual(data[i], 0, accuracy: 0.0001, "sample \(i) should be silent")
        }
    }

    func testEmptyEventListReturnsNil() {
        XCTAssertNil(ToneSequence.render(events: [], volume: 0.25, format: format))
    }

    /// The scale path is now a caller, and it must lay notes out exactly as it
    /// did before: evenly spaced, each sounding 90% of the gap so the notes are
    /// separated rather than slurred.
    func testScalePlayerStillProducesTheSameLengthBuffer() throws {
        let notes = ["C4", "D4", "E4"].compactMap { Note.named($0) }
        XCTAssertEqual(notes.count, 3)
        let buffer = try XCTUnwrap(ScalePlayer.render(notes: notes, interval: 0.5,
                                                      volume: 0.25, format: format))
        // Two gaps of 0.5 plus a final note of 0.45.
        XCTAssertEqual(Double(buffer.frameLength) / 48_000, 1.45, accuracy: 0.01)
    }
}
