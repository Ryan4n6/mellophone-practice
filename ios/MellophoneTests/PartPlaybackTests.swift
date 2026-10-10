import XCTest
import AVFoundation
@testable import Mellophone

/// The part, by ear.
///
/// `ScalePitchTests` exists because every other audio test would pass with the
/// app playing A440 for every note. The same is true here with one more way to
/// be wrong: a part is cut into chunks and laid end to end, so a note can be at
/// the right pitch and in the wrong PLACE. This renders the chunks exactly as
/// the player queues them, joins them, and names the note sounding at each
/// position the timeline says a note is.
///
/// The detector is `Pitch`, which `ScalePitchTests` calibrates against tones of
/// known frequency before it is allowed to judge anything.
final class PartPlaybackTests: XCTestCase {

    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    /// Cents. The same bar `ScalePitchTests` holds the scales to.
    private let tolerance = 15.0

    private func fixtureScore() throws -> Score {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "one-octave-f-major", withExtension: "pdf"))
        return try ScoreImporter.readOrThrow(url: url)
    }

    /// Render every chunk and join them, which is all the player does.
    private func rendered(_ timeline: PartTimeline) throws -> AVAudioPCMBuffer {
        let chunks = timeline.chunks(sampleRate: format.sampleRate, minimumSeconds: 1)
        let total = chunks.reduce(0) { $0 + $1.frames }
        let joined = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        joined.frameLength = AVAudioFrameCount(total)
        let out = try XCTUnwrap(joined.floatChannelData)[0]
        for chunk in chunks {
            let buffer = try XCTUnwrap(PartPlayer.render(chunk, volume: 0.5, format: format))
            XCTAssertEqual(Int(buffer.frameLength), chunk.frames,
                           "a chunk is placed by its length, so the length has to be exact")
            let source = try XCTUnwrap(buffer.floatChannelData)[0]
            for i in 0..<chunk.frames { out[chunk.startFrame + i] = source[i] }
        }
        return joined
    }

    /// The steady middle of a note, clear of the attack's filter sweep and of
    /// the release, for the reason given in `ScalePitchTests`.
    private func heard(_ entry: PartTimeline.Entry, in buffer: AVAudioPCMBuffer) -> Double? {
        Pitch.fundamental(of: buffer,
                          from: entry.start + entry.duration * 0.35,
                          to: entry.start + entry.duration * 0.75)
    }

    /// The PDF we authored, read by the real reader, played at a tempo that
    /// puts the chunk seams in the middle of the part.
    func testTheAuthoredScaleSoundsItsOwnNotesInTheirOwnPlaces() throws {
        let score = try fixtureScore()
        let timeline = PartTimeline(score: score, voice: .line(0), measures: 1...4, bpm: 120)
        let buffer = try rendered(timeline)
        XCTAssertGreaterThan(timeline.chunks(sampleRate: format.sampleRate, minimumSeconds: 1).count, 1,
                             "this has to cross a seam to mean anything")

        let expected = ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5",
                        "F5", "E5", "D5", "C5", "Bb4", "A4", "G4", "F4"]
        XCTAssertEqual(timeline.entries.count, expected.count)
        for (entry, name) in zip(timeline.entries, expected) {
            let note = try XCTUnwrap(Note.named(name))
            let frequency = try XCTUnwrap(heard(entry, in: buffer), "\(name) at \(entry.start) s is silent")
            XCTAssertEqual(Pitch.cents(frequency, note.frequency), 0, accuracy: tolerance,
                           "at \(entry.start) s: should be \(name), heard \(Int(frequency)) Hz")
        }
    }

    /// The control. Play bars 3 to 4 and listen for what bars 1 to 2 would
    /// have been: every note has to come out WRONG, or the test above cannot
    /// tell a part from its neighbour.
    func testTheWrongBarsAreActuallyHeardAsWrong() throws {
        let score = try fixtureScore()
        let timeline = PartTimeline(score: score, voice: .line(0), measures: 3...4, bpm: 120)
        let buffer = try rendered(timeline)
        let firstHalf = ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5"]

        var wrong = 0
        for (entry, name) in zip(timeline.entries, firstHalf) {
            let note = try XCTUnwrap(Note.named(name))
            guard let frequency = heard(entry, in: buffer) else { continue }
            if abs(Pitch.cents(frequency, note.frequency)) > tolerance { wrong += 1 }
        }
        XCTAssertEqual(wrong, 8, "bars 3 and 4 descend, so not one note matches the ascent")
    }

    /// Half speed is the same notes, twice as far apart. If tempo leaked into
    /// pitch, slowing a part down to learn it would teach it in the wrong key.
    func testSlowingDownMovesTheNotesAndNotThePitch() throws {
        let score = try fixtureScore()
        let slow = PartTimeline(score: score, voice: .line(0), measures: 1...1, bpm: 60)
        let buffer = try rendered(slow)
        XCTAssertEqual(Double(buffer.frameLength) / format.sampleRate, 4, accuracy: 0.001)
        for (entry, name) in zip(slow.entries, ["F4", "G4", "A4", "Bb4"]) {
            let note = try XCTUnwrap(Note.named(name))
            let frequency = try XCTUnwrap(heard(entry, in: buffer))
            XCTAssertEqual(Pitch.cents(frequency, note.frequency), 0, accuracy: tolerance, name)
        }
    }

    /// A bar of rest is a bar of silence of the right length, and the bar after
    /// it starts where it should. Collapsing the rest is the bug this catches:
    /// the part would still sound like the part, only early.
    func testARestTakesItsTimeAndIsSilent() throws {
        let events = [
            ScoreEvent(note: Note.named("G4"), writtenName: "G4", outOfRangeName: nil,
                       onsetBeats: 0, durationBeats: 4, measure: 1, voice: 0),
            ScoreEvent(note: nil, writtenName: "", outOfRangeName: nil,
                       onsetBeats: 4, durationBeats: 4, measure: 2, voice: 0),
            ScoreEvent(note: Note.named("C5"), writtenName: "C5", outOfRangeName: nil,
                       onsetBeats: 8, durationBeats: 4, measure: 3, voice: 0),
        ]
        let score = Score(events: events, timeSignature: (4, 4), keySignature: 0, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: [])
        let timeline = PartTimeline(score: score, voice: .line(0), measures: 1...3, bpm: 240)
        let buffer = try rendered(timeline)
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        let rate = format.sampleRate

        XCTAssertEqual(Double(buffer.frameLength) / rate, 3, accuracy: 0.001)
        // Bar 2 runs from 1 s to 2 s.
        var peak: Float = 0
        for i in Int(1.02 * rate)..<Int(1.98 * rate) { peak = max(peak, abs(data[i])) }
        XCTAssertEqual(peak, 0, accuracy: 0.0001, "the bar of rest is not silent")

        let after = try XCTUnwrap(Pitch.fundamental(of: buffer, from: 2.35, to: 2.75))
        XCTAssertEqual(Pitch.cents(after, try XCTUnwrap(Note.named("C5")).frequency), 0, accuracy: tolerance)
    }

    /// The count-in is one bar long to the sample, so the first note lands on
    /// the beat the clicks were counting.
    func testTheCountInIsExactlyOneBarLong() throws {
        let score = try fixtureScore()
        for bpm in [60.0, 97, 137, 220] {
            let timeline = PartTimeline(score: score, voice: .line(0), measures: 1...4, bpm: bpm)
            let clicks = PartPlayer.countIn(for: timeline, format: format)
            XCTAssertEqual(clicks.count, 4)
            let frames = clicks.reduce(0) { $0 + Int($1.frameLength) }
            XCTAssertEqual(frames, Int((4 * 60 / bpm * format.sampleRate).rounded()), "at \(bpm)")
        }
    }
}

/// The real player on the real engine.
///
/// Like `ScalePlaybackTests`, these prove the calls are accepted and the state
/// is right, and cannot prove anything was HEARD: `PartPlaybackTests` above is
/// what listens. They share that suite's weakness too. On a machine running two
/// builds at once the audio server can time out inside `AURemoteIO`, which is
/// the machine and not this code. Run this suite alone before believing a
/// failure here.
final class PartPlayerTests: XCTestCase {

    private func timeline(bpm: Double = 200) throws -> PartTimeline {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "one-octave-f-major", withExtension: "pdf"))
        return PartTimeline(score: try ScoreImporter.readOrThrow(url: url),
                            voice: .line(0), measures: 1...4, bpm: bpm)
    }

    func testPlayStartsOnTheCountInAndStopClearsEverything() throws {
        let player = PartPlayer()
        player.play(try timeline(), countIn: true, loop: false, volume: 0.2)
        XCTAssertTrue(player.isPlaying, "play() left the player stopped")
        XCTAssertEqual(player.countInBeat, 1)
        XCTAssertNil(player.currentSlot, "no note is sounding during the count-in")

        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.countInBeat)
        XCTAssertNil(player.currentSlot)
        XCTAssertNil(player.currentMeasure)
    }

    func testWithoutACountInTheFirstNoteIsCurrentAtOnce() throws {
        let player = PartPlayer()
        player.play(try timeline(), countIn: false, loop: true, volume: 0.2)
        XCTAssertTrue(player.isPlaying)
        XCTAssertNil(player.countInBeat)
        XCTAssertEqual(player.currentSlot, 0)
        XCTAssertEqual(player.currentMeasure, 1)
        player.stop()
    }

    /// Opening a second chart, or pressing Play on a new range, reuses the one
    /// player. It has to replace what was running, not stack on top of it.
    func testPlayingAgainReplacesWhatWasRunning() throws {
        let player = PartPlayer()
        player.play(try timeline(), countIn: true, loop: true, volume: 0.2)
        player.play(try timeline(bpm: 90), countIn: false, loop: false, volume: 0.2)
        XCTAssertTrue(player.isPlaying)
        XCTAssertNil(player.countInBeat, "the second run has no count-in, so the first one's must be gone")
        XCTAssertEqual(player.currentSlot, 0)
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: - What actually comes out of the engine

    /// Everything the engine's mixer puts out, recorded as it plays.
    private final class Recorder {
        private let lock = NSLock()
        private var samples: [Double] = []
        private(set) var sampleRate: Double = 0

        func attach(to mixer: AVAudioMixerNode) {
            let format = mixer.outputFormat(forBus: 0)
            sampleRate = format.sampleRate
            mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let self, let channel = buffer.floatChannelData?[0] else { return }
                let chunk = (0..<Int(buffer.frameLength)).map { Double(channel[$0]) }
                self.lock.withLock { self.samples.append(contentsOf: chunk) }
            }
        }

        func take() -> [Double] { lock.withLock { samples } }
    }

    /// Not a rendered buffer this time. The real player, on the real engine,
    /// with a tap on the mixer recording what it actually put out, in real
    /// time. This is the only test that would notice the scheduling being
    /// wrong: a chunk queued late, a seam with a hole in it, a count-in that
    /// does not lead into the first bar, or a player that claims to be playing
    /// and is silent.
    ///
    /// It is checked two ways, because each can be fooled alone. The recording
    /// is compared sample for sample with the count-in and the chunks laid end
    /// to end, which proves the SCHEDULE but would pass if the renderer itself
    /// played wrong notes. And the pitch detector names every note against the
    /// note table, which proves the NOTES but is too coarse to see a seam a
    /// few milliseconds out.
    ///
    /// An earlier version looked for the first loud sample of each note and
    /// failed twice on a player that was right: a note ramps up, so "loud"
    /// arrives milliseconds late, and the mixer pans a mono source to stereo
    /// 3 dB down, which moved the crossing again. Comparing whole signals has
    /// neither problem and no threshold to tune.
    ///
    /// It is still the simulator's audio engine and not a phone's speaker.
    func testWhatTheEngineActuallyPlaysIsThePartInTime() throws {
        let bpm = 120.0
        let timeline = try timeline(bpm: bpm)
        let volume = 0.4

        let player = PartPlayer()
        let recorder = Recorder()
        // The engine has to exist before it can be tapped.
        let format = try AudioEngineHost.shared.start()
        // Bars are two seconds here, so chunks are two bars and there is a seam
        // at four seconds, between the two F5s in the middle of the scale.
        let chunks = timeline.chunks(sampleRate: format.sampleRate)
        XCTAssertEqual(chunks.count, 2, "the part has to cross a seam")

        recorder.attach(to: AudioEngineHost.shared.engine.mainMixerNode)
        defer { AudioEngineHost.shared.engine.mainMixerNode.removeTap(onBus: 0) }

        player.play(timeline, countIn: true, loop: false, volume: volume)
        XCTAssertTrue(player.isPlaying)

        // Four clicks at 120 is two seconds, the part is eight more.
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !player.isPlaying }, object: nil)
        wait(for: [finished], timeout: 30)
        // Let the tail of the last buffer reach the tap.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let samples = recorder.take()
        let rate = recorder.sampleRate
        XCTAssertEqual(rate, format.sampleRate, "the comparison below is sample for sample")

        // What should have come out: the clicks, then the chunks, end to end.
        var expected: [Double] = []
        let buffers = PartPlayer.countIn(for: timeline, format: format)
            + (try chunks.map { try XCTUnwrap(PartPlayer.render($0, volume: volume, format: format)) })
        for buffer in buffers {
            let data = try XCTUnwrap(buffer.floatChannelData)[0]
            expected.append(contentsOf: (0..<Int(buffer.frameLength)).map { Double(data[$0]) })
        }
        XCTAssertEqual(Double(expected.count) / rate, 10, accuracy: 0.001)

        // Find where the run starts in the recording: the first sound is the
        // first click, give or take the few samples its fade-in takes to rise,
        // so the exact start is searched for around it.
        let firstSound = try XCTUnwrap(samples.firstIndex { abs($0) > 0.02 },
                                       "nothing came out of the engine at all")
        /// The level the recording is at relative to what was rendered, and
        /// how much of the recording is NOT explained by it, as a fraction.
        func fit(from start: Int, count: Int) -> (gain: Double, residual: Double)? {
            guard start >= 0, start + count <= samples.count, count <= expected.count else { return nil }
            var cross = 0.0, power = 0.0
            for k in 0..<count { cross += samples[start + k] * expected[k]; power += expected[k] * expected[k] }
            guard power > 0 else { return nil }
            let gain = cross / power
            var error = 0.0
            for k in 0..<count { let d = samples[start + k] - gain * expected[k]; error += d * d }
            return (gain, (error / (gain * gain * power)).squareRoot())
        }
        let start = try XCTUnwrap(
            (-64...64).map { firstSound + $0 }
                .compactMap { at in fit(from: at, count: 20_000).map { (at, $0.residual) } }
                .min { $0.1 < $1.1 }?.0,
            "the recording is too short to line up")

        // Schedule. All ten seconds, every click, every note, both seams.
        let whole = try XCTUnwrap(fit(from: start, count: expected.count),
                                  "the engine put out less than the part is long")
        XCTAssertLessThan(whole.residual, 0.01,
                          "what was played differs from the part laid end to end by \(whole.residual * 100)%")
        // The mixer is free to pan a mono source down, so the level is only
        // required to be a level: not silent and not louder than rendered.
        XCTAssertGreaterThan(whole.gain, 0.5)
        XCTAssertLessThan(whole.gain, 1.01)

        // Notes. Named against the table, not against our own renderer.
        let countIn = 4 * 60 / bpm
        let names = ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5",
                     "F5", "E5", "D5", "C5", "Bb4", "A4", "G4", "F4"]
        for (entry, name) in zip(timeline.entries, names) {
            let from = start + Int((countIn + entry.start + entry.duration * 0.35) * rate)
            let to = start + Int((countIn + entry.start + entry.duration * 0.75) * rate)
            let heard = try XCTUnwrap(Pitch.fundamental(of: Array(samples[from..<to]), sampleRate: rate),
                                      "\(name) at \(entry.start) s is silent")
            XCTAssertEqual(Pitch.cents(heard, try XCTUnwrap(Note.named(name)).frequency), 0, accuracy: 15,
                           "at \(entry.start) s: should be \(name), heard \(Int(heard)) Hz")
        }
    }

    /// The control for the test above. The same comparison, against the part
    /// with its two chunks swapped, has to FAIL to line up. Without this the
    /// residual could be small for any two recordings of roughly the same
    /// thing and the test above would prove nothing about order.
    func testTheComparisonNoticesChunksInTheWrongOrder() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let timeline = try timeline(bpm: 120)
        let chunks = timeline.chunks(sampleRate: format.sampleRate)
        func signal(_ order: [PartTimeline.Chunk]) throws -> [Double] {
            try order.flatMap { chunk -> [Double] in
                let buffer = try XCTUnwrap(PartPlayer.render(chunk, volume: 0.4, format: format))
                let data = try XCTUnwrap(buffer.floatChannelData)[0]
                return (0..<Int(buffer.frameLength)).map { Double(data[$0]) }
            }
        }
        let right = try signal(chunks)
        let swapped = try signal(chunks.reversed())
        var cross = 0.0, power = 0.0
        for k in 0..<right.count { cross += swapped[k] * right[k]; power += right[k] * right[k] }
        let gain = cross / power
        var error = 0.0
        for k in 0..<right.count { let d = swapped[k] - gain * right[k]; error += d * d }
        // Against itself this is zero. Against the wrong order it is nowhere
        // near the 1% the real test allows.
        XCTAssertGreaterThan((error / power).squareRoot(), 0.5)
    }

    func testARangeWithNothingInItDoesNotStart() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "one-octave-f-major", withExtension: "pdf"))
        let empty = PartTimeline(score: try ScoreImporter.readOrThrow(url: url),
                                 voice: .line(0), measures: 90...99, bpm: 100)
        let player = PartPlayer()
        player.play(empty, countIn: true, loop: false, volume: 0.2)
        XCTAssertFalse(player.isPlaying, "there is nothing to play, so nothing should claim to be playing")
    }
}
