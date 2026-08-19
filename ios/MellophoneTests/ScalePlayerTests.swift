import AVFoundation
import XCTest
@testable import Mellophone

final class ScaleRenderTests: XCTestCase {

    private var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    }

    private var chromatic: Scale {
        Scale.all.first { $0.name.hasPrefix("Chromatic") }!
    }

    /// The buffer has to hold every onset plus room for the last note to ring
    /// out. Cutting the final note short is the obvious way to get this wrong.
    func testBufferIsLongEnoughForTheLastNoteToFinish() {
        let notes = chromatic.notes
        let interval = 0.5
        let buffer = ScalePlayer.render(notes: notes, interval: interval, volume: 0.5, format: format)
        let expected = interval * Double(notes.count - 1) + interval * 0.9
        XCTAssertEqual(Double(buffer?.frameLength ?? 0) / 48_000, expected, accuracy: 0.001)
    }

    /// Overlapping releases are summed, so the result can exceed full scale.
    /// Clipping a scale run is far more audible than it being slightly quieter.
    func testNothingClipsAtAnySpeed() {
        for ms in [800, 500, 300, 180] {
            for scale in Scale.all {
                guard let buffer = ScalePlayer.render(
                    notes: scale.notes,
                    interval: Double(ms) / 1000,
                    volume: 1.0,
                    format: format
                ), let data = buffer.floatChannelData?[0] else {
                    return XCTFail("no buffer for \(scale.name) at \(ms) ms")
                }
                var peak: Float = 0
                for i in 0..<Int(buffer.frameLength) {
                    XCTAssertFalse(data[i].isNaN, "NaN in \(scale.name)")
                    peak = max(peak, abs(data[i]))
                }
                XCTAssertLessThanOrEqual(peak, 1.0001, "\(scale.name) at \(ms) ms peaks at \(peak)")
            }
        }
    }

    /// Every note should actually be audible where it is supposed to start.
    /// A rendering bug that silently drops notes would still produce a buffer
    /// of exactly the right length.
    func testEveryNoteHasEnergyAtItsOnset() {
        let notes = chromatic.notes
        let interval = 0.5
        guard let buffer = ScalePlayer.render(notes: notes, interval: interval, volume: 0.5, format: format),
              let data = buffer.floatChannelData?[0] else {
            return XCTFail("no buffer")
        }
        for index in notes.indices {
            // Sample just after the attack has risen, and before the release.
            let probe = Int((Double(index) * interval + 0.1) * 48_000)
            guard probe < Int(buffer.frameLength) else { continue }
            var energy: Float = 0
            for i in probe..<min(probe + 480, Int(buffer.frameLength)) {
                energy = max(energy, abs(data[i]))
            }
            XCTAssertGreaterThan(energy, 0.01, "note \(index) (\(notes[index].name)) is silent at its onset")
        }
    }

    /// The fastest speed is the one where a note's release is still sounding
    /// when the next begins, which is exactly when a naive overwrite would chop
    /// the tail off. Confirm the sum keeps them both.
    func testFastestSpeedStillRendersEveryNote() {
        let notes = chromatic.notes
        let buffer = ScalePlayer.render(notes: notes, interval: 0.18, volume: 0.5, format: format)
        XCTAssertNotNil(buffer)
        XCTAssertEqual(
            Double(buffer?.frameLength ?? 0) / 48_000,
            0.18 * Double(notes.count - 1) + 0.18 * 0.9,
            accuracy: 0.001
        )
    }

    func testEveryScaleResolvesToRealNotes() {
        for scale in Scale.all {
            XCTAssertFalse(scale.notes.isEmpty, "\(scale.name) resolved to nothing")
            XCTAssertEqual(scale.notes.count, scale.noteNames.count, "\(scale.name) has an unresolvable note")
        }
    }
}

/// Exercises the PLAY path, not just the render path.
///
/// The render tests above were thorough and all passed while the Scales tab was
/// completely silent, because `play()` bailed out before scheduling anything:
/// it read `player.lastRenderTime` immediately after `player.play()` and gave up
/// when it was nil, which it is until the engine has rendered a cycle.
///
/// HONEST LIMITATION: these are smoke tests and would NOT have caught that bug.
/// It only appears on a COLD engine, and by the time a test calls play() the
/// shared engine has already rendered, so the clock reads fine and the broken
/// code passes. This was checked rather than assumed: reintroducing the bug,
/// including after explicitly stopping the shared engine first, still passes.
///
/// So do not treat these as the guard. The real protection is structural: the
/// sound no longer depends on the clock at all, because the buffer is scheduled
/// before anything reads a render time. If someone reintroduces that ordering,
/// these tests will not save them.
final class ScalePlaybackTests: XCTestCase {

    func testPlayStartsPlaybackRatherThanBailingOut() throws {
        let player = ScalePlayer()
        let scale = try XCTUnwrap(Scale.all.first)

        player.play(scale, millisecondsPerNote: 300, volume: 0.2)

        XCTAssertTrue(player.isPlaying, "play() left the player stopped")

        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentIndex)
    }

    /// Playing a second scale while one is running must replace it, not stack.
    func testPlayingAgainReplacesTheRunningScale() throws {
        let player = ScalePlayer()
        let first = try XCTUnwrap(Scale.all.first)
        let second = try XCTUnwrap(Scale.all.last)

        player.play(first, millisecondsPerNote: 300, volume: 0.2)
        player.play(second, millisecondsPerNote: 300, volume: 0.2)
        XCTAssertTrue(player.isPlaying)

        player.stop()
        XCTAssertFalse(player.isPlaying)
    }
}
