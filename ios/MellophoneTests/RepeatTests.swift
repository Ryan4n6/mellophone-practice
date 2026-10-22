import XCTest
@testable import Mellophone

/// Repeats and 1st and 2nd endings (#46): read off the page, unrolled into the
/// bars a band plays, and played in that order.
///
/// What is real here, said once:
/// - `repeats.pdf` is a real engraved PDF, exported by MuseScore 4 from a
///   MusicXML file written for this test. It is OURS and in git, and it holds
///   every repeat shape listed at the top of `repeats.musicxml`.
/// - The play order tests build their marks by hand, because the order is
///   arithmetic on bar numbers and needs no page.
/// - The Florida and PEAK tests read Sam's charts, only on a machine that has
///   them: copyrighted, gitignored, never in a build.
final class RepeatTests: XCTestCase {

    /// The fixture as a band plays it, from the comment in its MusicXML.
    private let fixtureOrder = [1, 2, 1, 2, 3, 4, 5, 3, 4, 6, 7, 8, 9, 10, 11, 12, 9, 10, 13, 14, 15, 16]

    // MARK: - The order

    func testAPageWithNoRepeatsPlaysStraightThrough() {
        XCTAssertEqual(PlayOrder.bars(Array(1...5), repeats: Repeats()), [1, 2, 3, 4, 5])
    }

    func testEveryShapeInTheFixtureUnrollsTheWayABandPlaysIt() {
        let repeats = Repeats(starts: [3, 9], ends: [2, 5, 12], endings: [5: [1], 6: [2], 11: [1], 13: [2]])
        XCTAssertEqual(PlayOrder.bars(Array(1...16), repeats: repeats), fixtureOrder)
    }

    /// Florida's shape: in at 7, 1st ending 37 to 38, 2nd ending from 39.
    func testThe1stEndingIsSkippedTheSecondTimeThrough() {
        let repeats = Repeats(starts: [7], ends: [38], endings: [37: [1], 39: [2]])
        XCTAssertEqual(PlayOrder.bars(Array(1...42), repeats: repeats),
                       Array(1...38) + Array(7...36) + Array(39...42))
    }

    /// "1. 2." under one bracket and "3." after it: the repeat is taken twice.
    func testAnEndingForTwoPassesTakesTheRepeatTwice() {
        let repeats = Repeats(starts: [1], ends: [3], endings: [3: [1, 2], 4: [3]])
        XCTAssertEqual(PlayOrder.bars(Array(1...4), repeats: repeats), [1, 2, 3, 1, 2, 3, 1, 2, 4])
    }

    /// An end repeat after a finished repeat goes back to the bar after it,
    /// not to the top of the piece.
    func testASecondEndRepeatWithNoStartGoesBackToTheBarAfterTheFirst() {
        let repeats = Repeats(ends: [2, 4])
        XCTAssertEqual(PlayOrder.bars(Array(1...5), repeats: repeats), [1, 2, 1, 2, 3, 4, 3, 4, 5])
    }

    /// A range of bars plays from the first time its first bar comes up to
    /// the next time its last bar does.
    func testARangeIsCutFromThePerformanceNotThePage() {
        let order = Array(1...38) + Array(7...36) + Array(39...42)
        XCTAssertEqual(PlayOrder.slice(order, from: 7, to: 42), Array(7...38) + Array(7...36) + Array(39...42),
                       "opening at the entrance takes the repeat")
        XCTAssertEqual(PlayOrder.slice(order, from: 37, to: 38), [37, 38], "a loop of the 1st ending stays two bars")
        XCTAssertEqual(PlayOrder.slice(order, from: 20, to: 30), Array(20...30), "a stretch inside the repeat plays once")
        XCTAssertEqual(PlayOrder.slice(order, from: 30, to: 40), Array(30...38) + Array(7...36) + [39, 40],
                       "a range across the repeat goes round it")
        XCTAssertEqual(PlayOrder.slice(order, from: 50, to: 60), [])
    }

    func testTheOrderIsSaidInRuns() {
        XCTAssertEqual(PlayOrder.runs(Array(7...38) + Array(7...36) + Array(39...42)), "7 to 38, 7 to 36, 39 to 42")
        XCTAssertEqual(PlayOrder.runs([5, 3, 4, 6]), "5, 3 to 4, 6")
    }

    // MARK: - The page

    func testTheFixtureReadsEveryRepeatAndEnding() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "repeats", withExtension: "pdf"),
                                "the fixture is not in the test bundle")
        let score = try ScoreImporter.readOrThrow(url: url)
        // A start repeat at the head of a line was a barline closing an empty
        // bar, and every bar after it was numbered one high.
        XCTAssertEqual(score.events.map(\.measure), Array(1...16))
        XCTAssertEqual(score.repeats, Repeats(starts: [3, 9], ends: [2, 5, 12],
                                              endings: [5: [1], 6: [2], 11: [1], 13: [2]]))
        XCTAssertEqual(score.playOrder, fixtureOrder)
    }

    // MARK: - Playing it

    /// Two bars, marked 60 at bar 1 and 120 at bar 2, played 1 2 1 2.
    func testARepeatedBarPlaysAgainAtItsOwnTempo() {
        let events = (0..<8).map { index in
            ScoreEvent(note: Note.named("C5"), writtenName: "C5", outOfRangeName: nil,
                       onsetBeats: Double(index), durationBeats: 1, measure: index / 4 + 1, voice: 0)
        }
        let score = Score(events: events, timeSignature: (4, 4), keySignature: 0, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: [],
                          tempos: [TempoChange(measure: 1, onsetBeats: 0, printed: 60, noteQuarters: 1),
                                   TempoChange(measure: 2, onsetBeats: 4, printed: 120, noteQuarters: 1)],
                          repeats: Repeats(ends: [2]))
        let timeline = PartTimeline(score: score, voice: .line(0), bars: score.playOrder, bpm: 60)
        XCTAssertEqual(timeline.measures.map(\.number), [1, 2, 1, 2])
        XCTAssertEqual(timeline.measures.map(\.start), [0, 4, 6, 10])
        XCTAssertEqual(timeline.duration, 12, accuracy: 1e-9)
        XCTAssertEqual(timeline.entries.count, 16)
        XCTAssertEqual(Set(timeline.entries.map(\.slot)).count, 16, "every pass is its own moment to light")
        XCTAssertEqual(timeline.entries[8].start, 6, accuracy: 1e-9, "bar 1 again, back at 60")
        XCTAssertEqual(timeline.entries[8].duration, 1, accuracy: 1e-9)
        XCTAssertEqual(timeline.measure(at: 7), 1)
        XCTAssertEqual(timeline.beat(at: 7.5), 2)
    }

    /// A bar of rest, then |: 2 3 :| 4. The part opens at the entrance, bar
    /// 2, and Play takes the repeat; a range after it plays as printed.
    @MainActor
    func testThePartScreenPlaysTheRepeatAndSaysSo() throws {
        let events = [ScoreEvent(note: nil, writtenName: "", outOfRangeName: nil,
                                 onsetBeats: 0, durationBeats: 4, measure: 1, voice: 0)]
            + (2...4).map { bar in
                ScoreEvent(note: Note.named("C5"), writtenName: "C5", outOfRangeName: nil,
                           onsetBeats: Double(bar - 1) * 4, durationBeats: 4, measure: bar, voice: 0)
            }
        let model = PartModel()
        model.adopt(Score(events: events, timeSignature: (4, 4), keySignature: 0, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: [],
                          repeats: Repeats(starts: [2], ends: [3])))
        XCTAssertEqual(model.from, 2)
        let timeline = try XCTUnwrap(model.prepare(bpm: 60, instrument: .mellophone))
        XCTAssertEqual(timeline.measures.map(\.number), [2, 3, 2, 3, 4])
        XCTAssertEqual(model.repeatNote, "Takes the repeat: 2 to 3, 2 to 4.")
        XCTAssertEqual(model.rows.map(\.label), ["1", "2", "3", "4"], "the bar list stays the page")

        model.start(at: 4)
        XCTAssertEqual(model.prepare(bpm: 60, instrument: .mellophone)?.measures.map(\.number), [4])
        XCTAssertNil(model.repeatNote)
    }

    // MARK: - Sam's charts, where they exist

    private func local(_ name: String) throws -> Score {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/local/\(name)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) is not on this machine; the fixture test above still ran")
        }
        return try ScoreImporter.readOrThrow(url: url)
    }

    /// Checked against the printed page on 2026-10-22.
    func testFloridaGoesBackToBar7AndTakesThe2ndEnding() throws {
        let score = try local("Florida Fight Song (Orange and Blue)-Horn in F.pdf")
        XCTAssertEqual(score.repeats, Repeats(starts: [7], ends: [38], endings: [37: [1], 39: [2]]))
        XCTAssertEqual(score.playOrder, Array(1...38) + Array(7...36) + Array(39...42))
        XCTAssertEqual(score.events.map(\.measure).max(), 42, "the bar count is still the page's")
    }

    /// PEAK prints no repeat sign anywhere, and plays straight through.
    func testPEAKHasNoRepeats() throws {
        let score = try local("PEAK mello.pdf")
        XCTAssertEqual(score.repeats, Repeats())
        XCTAssertEqual(score.playOrder, Array(1...251))
    }
}
