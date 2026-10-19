import XCTest
@testable import Mellophone

/// What the part screen shows and what it would play: the bar list, the range,
/// and the words for each way an import can fail.
@MainActor
final class PartModelTests: XCTestCase {

    private func note(_ name: String, at onset: Double, bar: Int, beats: Double = 4, voice: Int = 0) -> ScoreEvent {
        ScoreEvent(note: Note.named(name), writtenName: name, outOfRangeName: nil,
                   onsetBeats: onset, durationBeats: beats, measure: bar, voice: voice)
    }

    private func rest(bar: Int) -> ScoreEvent {
        ScoreEvent(note: nil, writtenName: "", outOfRangeName: nil,
                   onsetBeats: Double(bar - 1) * 4, durationBeats: 4, measure: bar, voice: 0)
    }

    /// A note, five bars of rest with a flagged one in the middle, a note.
    private func model(voices: Int = 1) -> PartModel {
        let events = [note("G4", at: 0, bar: 1)]
            + (2...6).map(rest(bar:))
            + [note("C5", at: 24, bar: 7), note("D5", at: 28, bar: 9)]
        let model = PartModel()
        model.adopt(Score(events: events, timeSignature: (4, 4), keySignature: -4, voiceCount: voices,
                          suspectMeasures: [4], unreadableSymbols: []))
        return model
    }

    /// Sixteen rows that each say "rest" are sixteen rows to scroll past.
    func testARunOfEmptyBarsIsOneRow() {
        let rows = model().rows
        XCTAssertEqual(rows.map(\.label), ["1", "2 to 3", "4", "5 to 6", "7", "9"])
        XCTAssertEqual(rows.map(\.isRest), [false, true, true, true, false, false])
    }

    /// A flagged bar is flagged because the reader is unsure what is in it, so
    /// it never disappears into a run of rests it may not belong to.
    func testAFlaggedBarIsNeverFoldedIntoARun() {
        let rows = model().rows
        XCTAssertEqual(rows.filter(\.isSuspect).map(\.label), ["4"])
        XCTAssertEqual(model().row(holding: 3)?.label, "2 to 3")
        XCTAssertEqual(model().row(holding: 4)?.label, "4")
    }

    func testThePartOpensOnAllOfIt() {
        let model = model()
        XCTAssertEqual(model.from, 1)
        XCTAssertEqual(model.to, 9)
        XCTAssertTrue(model.isWholePart)
        XCTAssertEqual(model.describe(Score(events: [], timeSignature: (4, 4), keySignature: -4, voiceCount: 1,
                                            suspectMeasures: [], unreadableSymbols: [])),
                       "8 bars, 4/4, 4 flats")
    }

    // MARK: - The page's tempo (#41)

    /// Marked 120 at bar 1 and "Faster" 160 at bar 7, the shape of PEAK.
    private func markedModel() -> PartModel {
        let events = [note("G4", at: 0, bar: 1)] + (2...6).map(rest(bar:)) + [note("C5", at: 24, bar: 7)]
        let model = PartModel()
        model.adopt(Score(events: events, timeSignature: (4, 4), keySignature: -1, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: [],
                          tempos: [TempoChange(measure: 1, onsetBeats: 0, printed: 120, noteQuarters: 1),
                                   TempoChange(measure: 7, onsetBeats: 24, printed: 160, noteQuarters: 1)]))
        return model
    }

    /// What Sam asked for: the chart opens at the page's number, not the
    /// student's last one, and says so.
    func testAChartOpensAtThePageTempo() {
        let model = markedModel()
        XCTAssertEqual(model.printedTempo, 120)
        XCTAssertEqual(model.tempo(unprinted: 100), 120, "the student's stored 100 is for charts with no mark")
        XCTAssertTrue(model.isAtPageTempo)
        XCTAssertTrue(model.describe(Score(events: [], timeSignature: (4, 4), keySignature: -1, voiceCount: 1,
                                           suspectMeasures: [], unreadableSymbols: [],
                                           tempos: [TempoChange(measure: 1, onsetBeats: 0, printed: 120,
                                                                noteQuarters: 1)]))
                        .hasSuffix("1 flat, \u{2669} = 120"))
    }

    /// Slowed at bar 1, the "Faster" section opens slowed by the same share,
    /// and one tap puts it back to the page.
    func testSlowingDownIsAShareOfThePageThatFollowsTheRange() {
        let model = markedModel()
        for _ in 0..<6 { model.nudgeTempo(by: -5) }
        XCTAssertEqual(model.tempo(unprinted: 100), 90)
        XCTAssertFalse(model.isAtPageTempo)
        model.start(at: 7)
        XCTAssertEqual(model.printedTempo, 160)
        XCTAssertEqual(model.tempo(unprinted: 100), 120, "three quarters of 160")
        model.backToThePage()
        XCTAssertEqual(model.tempo(unprinted: 100), 160)
    }

    /// A chart that prints no tempo is the student's number, as before.
    func testAChartWithNoMarkUsesTheStudentsNumber() {
        let model = model()
        XCTAssertNil(model.printedTempo)
        XCTAssertEqual(model.tempo(unprinted: 84), 84)
        model.nudgeTempo(by: 5)
        XCTAssertEqual(model.tempo(unprinted: 84), 84, "the share does not apply where there is no page tempo")
    }

    /// Sam's opener sits out fifteen bars. Starting at bar 1 was 36 seconds of
    /// silence after the count-in, on a phone, with no band to count against.
    func testAPartThatOpensWithRestsStartsWhereThePlayerComesIn() throws {
        let events = (1...15).map(rest(bar:)) + [note("C5", at: 60, bar: 16), note("Bb4", at: 64, bar: 17)]
        let model = PartModel()
        model.adopt(Score(events: events, timeSignature: (4, 4), keySignature: -4, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: []))
        XCTAssertEqual(model.from, 16)
        XCTAssertEqual(model.to, 17)
        XCTAssertEqual(model.barsSkippedBeforeEntrance, 15)
        XCTAssertFalse(model.isWholePart, "the rests are still there to go back to")

        // What Play would actually queue: the first thing in it is the note.
        let timeline = try XCTUnwrap(model.prepare(bpm: 100, instrument: .mellophone))
        XCTAssertEqual(timeline.entries.first?.start, 0)
        XCTAssertEqual(timeline.entries.first?.event.note?.name, "C5")
        XCTAssertEqual(timeline.measures.first?.number, 16)

        model.selectWholePart()
        XCTAssertEqual(model.from, 1)
        XCTAssertEqual(model.barsSkippedBeforeEntrance, 0, "nothing is being skipped any more, so nothing says so")
    }

    /// A note above the horn has no row in the table and still sounds, so it
    /// is an entrance. Reading it as a rest would skip the player's first bar.
    func testAnOutOfRangeNoteIsAnEntrance() {
        let high = ScoreEvent(note: nil, writtenName: "D6", outOfRangeName: "D6",
                              onsetBeats: 8, durationBeats: 4, measure: 3, voice: 0)
        let model = PartModel()
        model.adopt(Score(events: [rest(bar: 1), rest(bar: 2), high, note("C5", at: 12, bar: 4)],
                          timeSignature: (4, 4), keySignature: 0, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: []))
        XCTAssertEqual(model.from, 3)
    }

    /// Nothing to skip to, so nothing is skipped.
    func testAPartOfNothingButRestsOpensWhole() {
        let model = PartModel()
        model.adopt(Score(events: (1...4).map(rest(bar:)), timeSignature: (4, 4), keySignature: 0, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: []))
        XCTAssertEqual(model.from, 1)
        XCTAssertEqual(model.to, 4)
        XCTAssertTrue(model.isWholePart)
        XCTAssertEqual(model.barsSkippedBeforeEntrance, 0)
    }

    /// Bar 8 does not exist in this part. The steppers walk the bars that do.
    func testTheSteppersWalkTheBarsThatExist() {
        let model = model()
        model.moveTo(by: -1)
        XCTAssertEqual(model.to, 7, "9 steps back to 7, not to a bar 8 that is not there")
        model.moveFrom(by: 1)
        XCTAssertEqual(model.from, 2)
        XCTAssertFalse(model.isWholePart)
        model.selectWholePart()
        XCTAssertTrue(model.isWholePart)
    }

    func testTheRangeCannotBeTurnedInsideOut() {
        let model = model()
        model.start(at: 7)
        model.end(at: 7)
        model.moveFrom(by: 1)
        XCTAssertEqual(model.from, 7, "from cannot pass to")
        model.moveTo(by: -1)
        XCTAssertEqual(model.to, 7, "to cannot pass from")
        model.moveFrom(by: -100)
        XCTAssertEqual(model.from, 7, "a step off the end of the part is ignored")
    }

    /// Tapping a bar past the end of the range starts there and plays to the
    /// end of the part, which is what "start here" means.
    func testStartingPastTheEndReopensTheEnd() {
        let model = model()
        model.end(at: 2)
        model.start(at: 7)
        XCTAssertEqual(model.from, 7)
        XCTAssertEqual(model.to, 9)
        model.end(at: 1)
        XCTAssertEqual(model.from, 1)
        XCTAssertEqual(model.to, 1)
    }

    func testPreparingPlaysOnlyTheRangeAndLightsWhatIsSounding() throws {
        let model = model()
        model.start(at: 7)
        let timeline = try XCTUnwrap(model.prepare(bpm: 120, instrument: .mellophone))
        XCTAssertEqual(timeline.entries.map(\.event.writtenName), ["C5", "D5"])
        XCTAssertEqual(model.eventIDs(inSlot: 1), [timeline.entries[1].id])
        XCTAssertEqual(model.entry(inSlot: 1)?.event.writtenName, "D5")
        XCTAssertTrue(model.eventIDs(inSlot: nil).isEmpty)
        XCTAssertEqual(model.entry(inSlot: nil)?.event.writtenName, "C5",
                       "with nothing playing the staff shows where Play would start")
    }

    func testTwoLinesAreTopAndBottomAndMoreAreNumbered() {
        XCTAssertEqual(model(voices: 2).voiceChoices.map(\.label), ["Top", "Bottom", "Both"])
        XCTAssertEqual(model(voices: 3).voiceChoices.map(\.label), ["Line 1", "Line 2", "Line 3", "All"])
    }

    /// Each failure sends the student somewhere different, so each has to be a
    /// different sentence.
    func testEveryFailureSaysSomethingDifferent() {
        let messages = [ImportError.cannotOpenFile, .noReadableNotation, .noStaffFound]
            .map { PartModel.message(for: $0) }
        XCTAssertEqual(Set(messages).count, 3)
        XCTAssertTrue(messages[0].contains("OneDrive"))
        XCTAssertTrue(messages[1].contains("scan"))
        XCTAssertTrue(messages[2].contains("staff"))
    }

    /// The real fixture through the real reader, off the main thread.
    func testLoadingTheAuthoredFixture() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "one-octave-f-major", withExtension: "pdf"))
        let model = PartModel()
        await model.load(Chart(url: url))
        guard case .ready(let score) = model.state else { return XCTFail("did not load") }
        XCTAssertEqual(model.describe(score), "4 bars, 4/4, 1 flat")
        XCTAssertEqual(model.rows.count, 4)
        XCTAssertEqual(model.rows.flatMap(\.entries).count, 16)
    }

    func testLoadingSomethingThatIsNotAPDFFailsWithItsMessage() async throws {
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID().uuidString).pdf")
        try Data("not a pdf".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        let model = PartModel()
        await model.load(Chart(url: junk))
        guard case .failed(let message) = model.state else { return XCTFail("should have failed") }
        XCTAssertEqual(message, PartModel.message(for: ImportError.cannotOpenFile))
    }

    // MARK: - One note

    /// The entry the bar list holds for the first `name` it shows.
    private func entry(_ name: String, in model: PartModel) throws -> PartTimeline.Entry {
        try XCTUnwrap(model.rows.flatMap(\.entries).first { $0.event.writtenName == name },
                      "no \(name) in the bar list")
    }

    /// Tapping a note is for looking at it with the horn up, so it goes on the
    /// staff and stays there, and what comes back is the pitch to sound.
    func testATappedNoteIsWhatTheStaffShowsAndItsOwnPitchIsWhatSounds() throws {
        let model = model()
        XCTAssertEqual(model.entry(inSlot: nil)?.event.writtenName, "G4", "with nothing tapped, the first note of the range")

        let frequency = model.pick(try entry("C5", in: model))
        XCTAssertEqual(frequency, try XCTUnwrap(Note.named("C5")).frequency)
        XCTAssertEqual(model.entry(inSlot: nil)?.event.writtenName, "C5")
        XCTAssertEqual(model.picked?.event.measure, 7)
    }

    /// What the tap SOUNDS is the horn's pitch for that note, not the page's
    /// (#24). The numbers are concert F4, Bb4 and Bb3, written out here and
    /// not computed, so this cannot agree with the app by sharing its sum.
    func testATappedNoteSoundsAtThePitchTheHornMakes() throws {
        let model = model()
        let c5 = try entry("C5", in: model)
        XCTAssertEqual(try XCTUnwrap(model.soundingFrequency(of: c5, on: .mellophone)), 349.23, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(model.soundingFrequency(of: c5, on: .frenchHorn)), 349.23, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(model.soundingFrequency(of: c5, on: .trumpet)), 466.16, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(model.soundingFrequency(of: c5, on: .euphonium)), 233.08, accuracy: 0.01)
        // The note check is handed the page's pitch and does this sum itself.
        // If `pick` ever returned the sounding one, it would be lowered twice.
        XCTAssertEqual(model.pick(c5), try XCTUnwrap(Note.named("C5")).frequency)

        let rest = try XCTUnwrap(model.rows.flatMap(\.entries).first { $0.event.isRest })
        XCTAssertNil(model.soundingFrequency(of: rest, on: .mellophone))
    }

    /// The timeline Play is handed is for the horn that is selected, and the
    /// one the bar list is laid out from is for nobody.
    func testWhatPlayQueuesIsForTheSelectedHorn() throws {
        let model = model()
        for instrument in Instrument.allCases {
            let heard = try XCTUnwrap(model.prepare(bpm: 100, instrument: instrument))
            XCTAssertEqual(heard.instrument, instrument)
            // The timeline that is PLAYED is the one a leak of sounding pitch
            // would show in. The bar list below is built with no instrument
            // and could not show it (#37).
            XCTAssertTrue(heard.entries.allSatisfy { $0.frequency == $0.event.note?.frequency },
                          "\(instrument): the played timeline's entries left the page's pitch")
        }
        XCTAssertTrue(model.rows.flatMap(\.entries).allSatisfy { $0.frequency == $0.event.note?.frequency },
                      "the bar list keeps the page's pitch, which is what the staff and the note check read")
    }

    /// A rest has nothing to hear and nothing to finger. Tapping one leaves
    /// the note that was being looked at where it is.
    func testTappingARestChangesNothing() throws {
        let model = model()
        model.pick(try entry("C5", in: model))
        let rest = try XCTUnwrap(model.rows.flatMap(\.entries).first { $0.event.isRest })
        XCTAssertNil(model.pick(rest))
        XCTAssertEqual(model.picked?.event.writtenName, "C5")
    }

    /// Once the passage plays, the staff follows the passage, and when it
    /// stops the staff goes back to where Play would start. A note tapped
    /// before that is over.
    func testPlayingOrMovingTheStartLetsGoOfTheTappedNote() throws {
        let model = model()
        model.pick(try entry("C5", in: model))
        _ = model.prepare(bpm: 100, instrument: .mellophone)
        XCTAssertNil(model.picked)
        XCTAssertEqual(model.entry(inSlot: 0)?.event.writtenName, "G4", "the run's first slot, not the old tap")

        model.pick(try entry("D5", in: model))
        model.start(at: 7)
        XCTAssertNil(model.picked)
        XCTAssertEqual(model.entry(inSlot: nil)?.event.writtenName, "C5", "the first note of the new range")
    }

    /// An out of range pitch has no row in the note table and still sounds,
    /// so it can still be tapped, at the pitch its name works out to.
    func testAnOutOfRangeNoteCanStillBeTapped() throws {
        let high = ScoreEvent(note: nil, writtenName: "D6", outOfRangeName: "D6",
                              onsetBeats: 0, durationBeats: 4, measure: 1, voice: 0)
        let model = PartModel()
        model.adopt(Score(events: [high], timeSignature: (4, 4), keySignature: 0, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: []))
        let frequency = try XCTUnwrap(model.pick(try entry("D6", in: model)))
        XCTAssertEqual(1200 * log2(frequency / 1174.66), 0, accuracy: 1, "D6 is 1174.66 Hz")
    }

    /// The card view's taps search these (#43). A divisi part with Top
    /// selected must not let a tap land on the bottom head, which is not in
    /// the bar list and would have moved the start bar instead of sounding.
    func testOnlyTheSelectedLineIsTappable() {
        let events = [note("C5", at: 0, bar: 1), note("A4", at: 0, bar: 1, voice: 1)]
        let model = PartModel()
        model.adopt(Score(events: events, timeSignature: (4, 4), keySignature: 0, voiceCount: 2,
                          suspectMeasures: [], unreadableSymbols: []))
        model.voice = .line(0)
        XCTAssertEqual(model.tappableEvents.map(\.writtenName), ["C5"])
        model.voice = .line(1)
        XCTAssertEqual(model.tappableEvents.map(\.writtenName), ["A4"])
    }
}
