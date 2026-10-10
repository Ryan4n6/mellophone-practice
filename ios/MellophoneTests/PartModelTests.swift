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
        let timeline = try XCTUnwrap(model.prepare(bpm: 100))
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
        let timeline = try XCTUnwrap(model.prepare(bpm: 120))
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
}
