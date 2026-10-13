import XCTest
@testable import Mellophone

/// What sounds when, with no audio in it.
///
/// `PartTimeline` is the whole answer to "which note is playing at second
/// 41.3 of bars 12 to 20 on the bottom line at 84", and it is arithmetic, so it
/// is tested as arithmetic. The player only puts these buffers end to end.
final class PartTimelineTests: XCTestCase {

    // MARK: - Building a score by hand

    private func note(_ name: String, at onset: Double, beats: Double, bar: Int, voice: Int = 0) -> ScoreEvent {
        ScoreEvent(note: Note.named(name), writtenName: name, outOfRangeName: nil,
                   onsetBeats: onset, durationBeats: beats, measure: bar, voice: voice)
    }

    private func rest(at onset: Double, beats: Double, bar: Int) -> ScoreEvent {
        ScoreEvent(note: nil, writtenName: "", outOfRangeName: nil,
                   onsetBeats: onset, durationBeats: beats, measure: bar, voice: 0)
    }

    private func score(_ events: [ScoreEvent], time: (beats: Int, unit: Int) = (4, 4),
                       units: [Int: Int] = [:], voices: Int = 1) -> Score {
        Score(events: events, timeSignature: time, keySignature: 0, voiceCount: voices,
              suspectMeasures: [], unreadableSymbols: [], beatUnits: units)
    }

    /// Three bars of quarter notes in 4/4, twelve beats.
    private func threeBars() -> Score {
        let names = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5", "D5", "E5", "F5", "G5"]
        return score(names.enumerated().map { index, name in
            note(name, at: Double(index), beats: 1, bar: index / 4 + 1)
        })
    }

    // MARK: - Tempo

    func testAQuarterNoteAtSixtyLastsOneSecond() {
        let timeline = PartTimeline(score: threeBars(), voice: .line(0), measures: 1...3, bpm: 60)
        XCTAssertEqual(timeline.entries.map(\.start), (0..<12).map(Double.init))
        XCTAssertTrue(timeline.entries.allSatisfy { $0.duration == 1 })
        XCTAssertEqual(timeline.duration, 12, accuracy: 1e-9)
        XCTAssertEqual(timeline.secondsPerPulse, 1, accuracy: 1e-9)
    }

    func testDoublingTheTempoHalvesEveryTime() {
        let timeline = PartTimeline(score: threeBars(), voice: .line(0), measures: 1...3, bpm: 120)
        XCTAssertEqual(timeline.entries[5].start, 2.5, accuracy: 1e-9)
        XCTAssertEqual(timeline.entries[5].duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(timeline.duration, 6, accuracy: 1e-9)
    }

    // MARK: - A range of bars

    /// Looping bars 2 to 3 has to start at zero, or the loop opens with a bar
    /// of silence where bar 1 used to be.
    func testARangeStartsAtZeroAndHoldsOnlyItsBars() {
        let timeline = PartTimeline(score: threeBars(), voice: .line(0), measures: 2...3, bpm: 60)
        XCTAssertEqual(timeline.entries.first?.event.writtenName, "G4")
        XCTAssertEqual(timeline.entries.first?.start, 0)
        XCTAssertEqual(timeline.measures, [.init(number: 2, start: 0), .init(number: 3, start: 4)])
        XCTAssertEqual(timeline.duration, 8, accuracy: 1e-9)
        XCTAssertEqual(timeline.entries.count, 8)
    }

    func testARangeWithNoBarsInItIsEmptyRatherThanACrash() {
        let timeline = PartTimeline(score: threeBars(), voice: .line(0), measures: 40...50, bpm: 60)
        XCTAssertTrue(timeline.entries.isEmpty)
        XCTAssertEqual(timeline.duration, 0)
        XCTAssertTrue(timeline.chunks(sampleRate: 48_000).isEmpty)
        XCTAssertNil(timeline.slot(at: 0))
    }

    // MARK: - Divisi

    /// A chord, then a unison, then a chord. The reader emits the highest head
    /// first and gives every head of a chord the same onset.
    private func divisi() -> Score {
        score([
            note("C5", at: 0, beats: 2, bar: 1), note("A4", at: 0, beats: 2, bar: 1, voice: 1),
            note("G4", at: 2, beats: 1, bar: 1),
            note("E5", at: 3, beats: 1, bar: 1), note("C5", at: 3, beats: 1, bar: 1, voice: 1),
        ], voices: 2)
    }

    func testTheTopLineIsTheHighestHeadOfEveryChord() {
        let timeline = PartTimeline(score: divisi(), voice: .line(0), measures: 1...1, bpm: 60)
        XCTAssertEqual(timeline.entries.map(\.event.writtenName), ["C5", "G4", "E5"])
    }

    /// Where the two parts meet on one note there is only one head, and the
    /// bottom line plays it. Dropping it would put a hole in the bottom part
    /// at every unison.
    func testTheBottomLineFollowsTheUnisons() {
        let timeline = PartTimeline(score: divisi(), voice: .line(1), measures: 1...1, bpm: 60)
        XCTAssertEqual(timeline.entries.map(\.event.writtenName), ["A4", "G4", "C5"])
        XCTAssertEqual(timeline.entries.map(\.start), [0, 2, 3])
    }

    func testBothLinesShareASlotSoTheyLightTogether() {
        let timeline = PartTimeline(score: divisi(), voice: .all, measures: 1...1, bpm: 60)
        XCTAssertEqual(timeline.entries.map(\.event.writtenName), ["C5", "A4", "G4", "E5", "C5"])
        XCTAssertEqual(timeline.entries.map(\.slot), [0, 0, 1, 2, 2])
        XCTAssertEqual(timeline.entries.map(\.start), [0, 0, 2, 3, 3])
    }

    // MARK: - Out of range

    /// The failure this guards against is the worst one available: a note above
    /// the fingering chart has no row in the note table, so `note` is nil, and
    /// if nil meant silence the part would sound right everywhere except the
    /// bars a student most needs to hear.
    func testANoteOutsideTheChartStillSounds() throws {
        let high = ScoreEvent(note: nil, writtenName: "D6", outOfRangeName: "D6",
                              onsetBeats: 0, durationBeats: 4, measure: 1, voice: 0)
        let timeline = PartTimeline(score: score([high]), voice: .line(0), measures: 1...1, bpm: 60)
        let frequency = try XCTUnwrap(timeline.entries.first?.frequency)
        // D6 in equal temperament at A440.
        XCTAssertEqual(frequency, 1174.659, accuracy: 0.01)
        XCTAssertEqual(timeline.chunks(sampleRate: 48_000).first?.events.count, 1,
                       "an out of range note has to reach the renderer")
    }

    /// The control for the test above: a real rest is silent. Without this the
    /// test passes for a timeline that gives EVERYTHING a frequency.
    func testARestHasNoFrequencyAndRendersNothing() {
        let timeline = PartTimeline(score: score([rest(at: 0, beats: 4, bar: 1)]),
                                    voice: .line(0), measures: 1...1, bpm: 60)
        XCTAssertEqual(timeline.entries.count, 1)
        XCTAssertNil(timeline.entries[0].frequency)
        let chunks = timeline.chunks(sampleRate: 48_000)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].events.isEmpty)
        XCTAssertEqual(chunks[0].frames, 192_000, "a bar of rest still takes a bar of time")
    }

    /// An out of range pitch is named in the SAME equal temperament as the
    /// table, or the note above C6 would be out of tune with the one below it.
    func testTheWorkedOutFrequencyAgreesWithTheTable() throws {
        for row in Note.all {
            let asIfOutOfRange = ScoreEvent(note: nil, writtenName: row.name, outOfRangeName: row.name,
                                            onsetBeats: 0, durationBeats: 1, measure: 1, voice: 0)
            let worked = try XCTUnwrap(PartTimeline.frequency(of: asIfOutOfRange), row.name)
            XCTAssertEqual(1200 * log2(worked / row.frequency), 0, accuracy: 1,
                           "\(row.name): worked out \(worked), table says \(row.frequency)")
        }
    }

    // MARK: - Whose pitch

    /// A part is rendered at the pitch the horn makes (#24). Written C5 is
    /// 523.25 Hz on the page and concert F4, Bb4 or Bb3 in the room. Every
    /// number is written out, none is computed from the app's own factor.
    ///
    /// Hand-built score. This checks what is ASKED of the renderer; what
    /// comes out of it is measured by ear in `PartPlaybackTests`.
    func testATimelineForAHornAsksForThePitchThatHornMakes() throws {
        let c5 = score([note("C5", at: 0, beats: 4, bar: 1)])
        let made: [(Instrument, Double)] = [(.mellophone, 349.23), (.frenchHorn, 349.23),
                                            (.trumpet, 466.16), (.euphonium, 233.08)]
        for (instrument, hertz) in made {
            let timeline = PartTimeline(score: c5, voice: .line(0), measures: 1...1, bpm: 60, sounding: instrument)
            let event = try XCTUnwrap(timeline.chunks(sampleRate: 48_000).first?.events.first)
            XCTAssertEqual(event.frequency, hertz, accuracy: 0.01, instrument.shortName)
            XCTAssertEqual(event.brightnessFloor, NoteCheck.referenceBrightnessFloor,
                           "\(instrument.shortName): a note this low needs the filter held open to be heard on a phone")
            XCTAssertEqual(try XCTUnwrap(timeline.entries.first?.frequency), 523.25, accuracy: 0.01,
                           "the entry keeps the page's pitch")
        }
    }

    /// With nobody named, the page is rendered as written and the tone is the
    /// one it always was. The bar list is laid out from one of these, and
    /// every test that names notes off the page depends on it.
    func testATimelineForNobodyIsThePageAsWritten() throws {
        let timeline = PartTimeline(score: score([note("C5", at: 0, beats: 4, bar: 1)]),
                                    voice: .line(0), measures: 1...1, bpm: 60)
        XCTAssertNil(timeline.instrument)
        let event = try XCTUnwrap(timeline.chunks(sampleRate: 48_000).first?.events.first)
        XCTAssertEqual(event.frequency, 523.25, accuracy: 0.01)
        XCTAssertEqual(event.brightnessFloor, 0)
    }

    /// A pitch over the top of the table is lowered like any other.
    func testAnOutOfRangeNoteIsLoweredToo() throws {
        let high = ScoreEvent(note: nil, writtenName: "D6", outOfRangeName: "D6",
                              onsetBeats: 0, durationBeats: 4, measure: 1, voice: 0)
        let timeline = PartTimeline(score: score([high]), voice: .line(0), measures: 1...1, bpm: 60,
                                    sounding: .mellophone)
        let event = try XCTUnwrap(timeline.chunks(sampleRate: 48_000).first?.events.first)
        // Written D6 on an F horn is concert G5.
        XCTAssertEqual(event.frequency, 783.99, accuracy: 0.01)
    }

    // MARK: - What a tempo number counts

    func testThePulseIsWhatGetsTheBeat() {
        XCTAssertEqual(Pulse.of((4, 4)).quarters, 1)
        XCTAssertEqual(Pulse.of((2, 4)).quarters, 1)
        XCTAssertEqual(Pulse.of((2, 2)).quarters, 2)
        XCTAssertEqual(Pulse.of((6, 8)).quarters, 1.5, "6/8 is felt in two dotted quarters")
        XCTAssertEqual(Pulse.of((12, 8)).quarters, 1.5)
        XCTAssertEqual(Pulse.of((7, 8)).quarters, 0.5, "7/8 does not divide into threes")
        XCTAssertEqual(Pulse.of((3, 8)).quarters, 0.5, "3/8 is one bar of three, not one beat")
    }

    /// 6/8 at 60 is sixty DOTTED QUARTERS a minute, so each eighth is a third of
    /// a second and the bar is two seconds. Counting eighths would make it six.
    func testSixEightAtSixtyIsTwoSecondsABar() {
        let eighths = (0..<6).map { note("G4", at: Double($0), beats: 1, bar: 1) }
        let timeline = PartTimeline(score: score(eighths, time: (6, 8)), voice: .line(0),
                                    measures: 1...1, bpm: 60)
        XCTAssertEqual(timeline.duration, 2, accuracy: 1e-9)
        XCTAssertEqual(timeline.entries[1].start, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(timeline.countInBeats, 2)
    }

    // MARK: - Phrases

    /// Three quarters, a rest, a note. The first three are one phrase and the
    /// rest is a breath, so the note after it starts from nothing again.
    func testNotesWithNoRestBetweenThemAreOnePhrase() {
        let events = [note("C4", at: 0, beats: 1, bar: 1), note("D4", at: 1, beats: 1, bar: 1),
                      note("E4", at: 2, beats: 1, bar: 1), rest(at: 3, beats: 1, bar: 1),
                      note("F4", at: 4, beats: 4, bar: 2)]
        let timeline = PartTimeline(score: score(events), voice: .line(0), measures: 1...2, bpm: 60)
        let sounding = timeline.entries.filter { $0.frequency != nil }
        XCTAssertEqual(sounding.map(\.articulation.tonguedIn), [false, true, true, false])
        XCTAssertEqual(sounding.map(\.articulation.carriesOn), [true, true, false, false])
        XCTAssertEqual(sounding.map(\.articulation.settleCents),
                       [PartTimeline.settleAfterABreath, PartTimeline.settleWhenTongued,
                        PartTimeline.settleWhenTongued, PartTimeline.settleAfterABreath])

        // A note running into the next is held for all of its written length.
        // Only the one before the rest, and the last, are clipped short.
        let rendered = timeline.chunks(sampleRate: 44_100, minimumSeconds: 100).flatMap(\.events)
        XCTAssertEqual(rendered.map(\.duration), [1, 1, 0.96, 3.96])
        XCTAssertEqual(rendered.map(\.articulation), sounding.map(\.articulation),
                       "the renderer has to be told, it cannot see the chunk before its own")
    }

    /// A phrase does not stop at the edge of a buffer. The last note of one
    /// chunk and the first of the next are still told they join.
    func testAPhraseCarriesAcrossAChunkSeam() {
        let timeline = PartTimeline(score: threeBars(), voice: .line(0), measures: 1...3, bpm: 60)
        let chunks = timeline.chunks(sampleRate: 44_100, minimumSeconds: 4)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].events.last?.articulation.carriesOn, true)
        XCTAssertEqual(chunks[1].events.first?.articulation.tonguedIn, true)
        XCTAssertEqual(chunks[2].events.last?.articulation.carriesOn, false, "the end of the range is a breath")
    }

    /// Divisi, both lines sounding. Each line runs on with the other.
    func testBothLinesOfADivisiPhraseRunOn() {
        let events = [note("E5", at: 0, beats: 2, bar: 1), note("C5", at: 0, beats: 2, bar: 1, voice: 1),
                      note("F5", at: 2, beats: 2, bar: 1), note("D5", at: 2, beats: 2, bar: 1, voice: 1)]
        let timeline = PartTimeline(score: score(events, voices: 2), voice: .all, measures: 1...1, bpm: 60)
        XCTAssertEqual(timeline.entries.map(\.articulation.carriesOn), [true, true, false, false])
        XCTAssertEqual(timeline.entries.map(\.articulation.tonguedIn), [false, false, true, true])
    }

    // MARK: - Counting

    /// Fifteen bars of rest is where a student loses their place, so the
    /// screen counts them.
    ///
    /// At 72 and not at a round tempo on purpose. A beat is 0.8333 s there,
    /// which floating point cannot hold, and a time that lands exactly on a
    /// beat divides out to 1.9999999999999998 as early as bar 2. At 100 the
    /// same arithmetic happens to come out whole and proves nothing.
    func testTheBeatCountsOneToFourInEveryBarOfARest() {
        let rests = (0..<8).map { rest(at: Double($0) * 4, beats: 4, bar: $0 + 1) }
        let timeline = PartTimeline(score: score(rests), voice: .line(0), measures: 1...8, bpm: 72)
        let pulse = 60.0 / 72
        for bar in 0..<8 {
            for beat in 0..<4 {
                let on = Double(bar * 4 + beat) * pulse
                XCTAssertEqual(timeline.beat(at: on), beat + 1, "bar \(bar + 1), on beat \(beat + 1)")
                XCTAssertEqual(timeline.beat(at: on + pulse * 0.98), beat + 1, "bar \(bar + 1), end of beat \(beat + 1)")
                XCTAssertEqual(timeline.measure(at: on + 0.001), bar + 1)
            }
        }
        XCTAssertNil(timeline.beat(at: -0.01))
        XCTAssertNil(timeline.beat(at: timeline.duration), "the end of the range is not a fifth beat")
    }

    /// 6/8 is counted in two, the same two the count-in clicks.
    func testSixEightCountsInTwo() {
        let eighths = (0..<12).map { note("G4", at: Double($0), beats: 1, bar: $0 / 6 + 1) }
        let timeline = PartTimeline(score: score(eighths, time: (6, 8)), voice: .line(0),
                                    measures: 1...2, bpm: 60)
        XCTAssertEqual([0, 0.99, 1, 1.99, 2, 2.99, 3, 3.99].map { timeline.beat(at: $0) },
                       [1, 1, 2, 2, 1, 1, 2, 2])
    }

    /// The count restarts at the bar line, so a short bar does not leave every
    /// bar after it out of step.
    func testTheCountRestartsAtEveryBarLine() {
        let short = [rest(at: 0, beats: 2, bar: 1), rest(at: 2, beats: 4, bar: 2)]
        let timeline = PartTimeline(score: score(short), voice: .line(0), measures: 1...2, bpm: 60)
        XCTAssertEqual([0, 1, 2, 3, 4, 5].map { timeline.beat(at: Double($0)) }, [1, 2, 1, 2, 3, 4])
    }

    func testTheCountInIsOneBarOfTheOpeningMeter() {
        func beats(_ time: (beats: Int, unit: Int)) -> Int {
            PartTimeline(score: score([note("G4", at: 0, beats: 1, bar: 1)], time: time),
                         voice: .line(0), measures: 1...1, bpm: 100).countInBeats
        }
        XCTAssertEqual(beats((4, 4)), 4)
        XCTAssertEqual(beats((3, 4)), 3)
        XCTAssertEqual(beats((2, 4)), 2)
        XCTAssertEqual(beats((2, 2)), 2)
        XCTAssertEqual(beats((7, 8)), 7)
    }

    /// A bar of 4/4 then a bar of 6/8. The reader counts the second bar's
    /// eighths as one beat each, because in 6/8 they are. Played back, an
    /// eighth has to stay an eighth across the change.
    private func meterChange(units: [Int: Int]) -> Score {
        let first = (0..<4).map { note("C5", at: Double($0), beats: 1, bar: 1) }
        let second = (0..<6).map { note("D5", at: 4 + Double($0), beats: 1, bar: 2) }
        return score(first + second, units: units)
    }

    func testAnEighthStaysAnEighthAcrossAMeterChange() {
        let timeline = PartTimeline(score: meterChange(units: [1: 4, 2: 8]), voice: .line(0),
                                    measures: 1...2, bpm: 60)
        XCTAssertEqual(timeline.measures[1].start, 4, accuracy: 1e-9)
        XCTAssertEqual(timeline.entries[5].duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(timeline.duration, 7, accuracy: 1e-9)
    }

    /// The control: with the units left out, the same bar comes out at quarter
    /// note speed, three seconds too long. That is the bug the units exist for.
    func testWithoutTheUnitsTheSecondBarDragsAtHalfSpeed() {
        let timeline = PartTimeline(score: meterChange(units: [:]), voice: .line(0),
                                    measures: 1...2, bpm: 60)
        XCTAssertEqual(timeline.duration, 10, accuracy: 1e-9)
    }

    // MARK: - Finding the note that is sounding

    func testTheSlotAtATimeIsTheNoteSoundingThen() {
        let timeline = PartTimeline(score: threeBars(), voice: .line(0), measures: 1...3, bpm: 60)
        XCTAssertEqual(timeline.slot(at: 0), 0)
        XCTAssertEqual(timeline.slot(at: 0.999), 0)
        XCTAssertEqual(timeline.slot(at: 1), 1)
        XCTAssertEqual(timeline.slot(at: 11.5), 11)
        XCTAssertNil(timeline.slot(at: 12), "the end of the part is not inside it")
        XCTAssertNil(timeline.slot(at: -0.1))
        XCTAssertEqual(timeline.measure(at: 7.9), 2)
        XCTAssertEqual(timeline.measure(at: 8), 3)
    }

    // MARK: - Chunks

    /// A tempo and a sample rate chosen so that nothing divides evenly. If the
    /// chunk lengths were added up from rounded bar lengths they would wander
    /// off the timeline, and over a long chart the highlight would slide away
    /// from the sound.
    func testChunksTileTheRangeWithNoGapAndNoOverlap() {
        var events: [ScoreEvent] = []
        for bar in 1...40 {
            for beat in 0..<3 {
                events.append(note("G4", at: Double((bar - 1) * 3 + beat), beats: 1, bar: bar))
            }
        }
        let timeline = PartTimeline(score: score(events, time: (3, 4)), voice: .line(0),
                                    measures: 1...40, bpm: 137)
        let rate = 44_100.0
        let chunks = timeline.chunks(sampleRate: rate)

        XCTAssertGreaterThan(chunks.count, 5, "40 bars is more than one buffer's worth")
        XCTAssertEqual(chunks.first?.startFrame, 0)
        for (before, after) in zip(chunks, chunks.dropFirst()) {
            XCTAssertEqual(before.startFrame + before.frames, after.startFrame)
        }
        let total = chunks.reduce(0) { $0 + $1.frames }
        XCTAssertEqual(total, Int((timeline.duration * rate).rounded()))
        XCTAssertEqual(chunks.reduce(0) { $0 + $1.events.count }, 120,
                       "every note lands in exactly one chunk")
        for chunk in chunks.dropLast() {
            XCTAssertGreaterThanOrEqual(Double(chunk.frames) / rate, 3 - 1 / rate)
        }
    }

    /// Nothing in a chunk may run past its end, since the next chunk is placed
    /// by this one's length and a note that overhung would be cut off there.
    func testNoNoteRunsPastTheEndOfItsChunk() {
        let timeline = PartTimeline(score: threeBars(), voice: .line(0), measures: 1...3, bpm: 60)
        let rate = 48_000.0
        for chunk in timeline.chunks(sampleRate: rate) {
            let length = Double(chunk.frames) / rate
            for event in chunk.events {
                XCTAssertGreaterThanOrEqual(event.onset, 0)
                XCTAssertLessThanOrEqual(event.onset + event.duration, length + 1e-9)
            }
        }
    }

    /// Two notes on one pitch are two notes. The gap that separates them is a
    /// tenth of a short note and never more than 40 ms of a long one.
    func testANoteSoundsAHairShortOfItsWrittenLength() {
        XCTAssertEqual(PartTimeline.sounding(0.2), 0.18, accuracy: 1e-9)
        XCTAssertEqual(PartTimeline.sounding(4), 3.96, accuracy: 1e-9)
    }
}
