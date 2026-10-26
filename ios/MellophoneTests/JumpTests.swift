import XCTest
@testable import Mellophone

/// D.S., D.C., the segno, the coda and Fine (#48): read off the page and
/// played the way a band plays them.
///
/// What is real here, said once:
/// - `jumps-ds.pdf` and `jumps-dc.pdf` are real engraved PDFs, exported by
///   MuseScore 4 from MusicXML written for this test (their comments list
///   every bar). They are OURS and in git. MuseScore prints the jump words
///   left-aligned over the bar they belong to, in Edwin, and the segno and
///   coda signs in BravuraText; that is what was measured. Sibelius and
///   Finale jumps have not been seen and are not mapped.
/// - The play order tests build their marks by hand, because the order is
///   arithmetic on bar numbers and needs no page.
final class JumpTests: XCTestCase {

    private func marks(segno: Int? = nil, coda: Int? = nil, toCoda: Int? = nil, fine: Int? = nil,
                       jumps: [Int: JumpSign], starts: Set<Int> = [], ends: Set<Int> = [],
                       endings: [Int: [Int]] = [:]) -> Repeats {
        var repeats = Repeats(starts: starts, ends: ends, endings: endings)
        repeats.segno = segno
        repeats.coda = coda
        repeats.toCoda = toCoda
        repeats.fine = fine
        repeats.jumps = jumps
        return repeats
    }

    // MARK: - The order

    func testDSAlCodaGoesBackToTheSignAndLeavesForTheCoda() {
        let repeats = marks(segno: 3, coda: 9, toCoda: 6, jumps: [8: JumpSign(back: .dalSegno, until: .coda)])
        XCTAssertEqual(PlayOrder.bars(Array(1...10), repeats: repeats), Array(1...8) + Array(3...6) + [9, 10])
    }

    func testDCAlFineGoesToTheTopAndStopsAtFine() {
        let repeats = marks(fine: 4, jumps: [6: JumpSign(back: .daCapo, until: .fine)])
        XCTAssertEqual(PlayOrder.bars(Array(1...6), repeats: repeats), Array(1...6) + Array(1...4))
    }

    /// The first time through, Fine and To Coda are read past: they only
    /// mean something on the way back.
    func testFineAndToCodaAreIgnoredTheFirstTime() {
        let repeats = marks(segno: 1, coda: 5, toCoda: 2, fine: 3, jumps: [4: JumpSign(back: .dalSegno, until: .coda)])
        XCTAssertEqual(PlayOrder.bars(Array(1...6), repeats: repeats), [1, 2, 3, 4, 1, 2, 5, 6])
    }

    func testAPlainDCPlaysToTheEndOnce() {
        let repeats = marks(jumps: [4: JumpSign(back: .daCapo, until: .end)])
        XCTAssertEqual(PlayOrder.bars(Array(1...4), repeats: repeats), [1, 2, 3, 4, 1, 2, 3, 4])
    }

    /// A plain D.C. on a page that prints Fine stops at it: that is what the
    /// Fine is there for.
    func testAPlainDCStopsAtAFineThePagePrints() {
        let repeats = marks(fine: 2, jumps: [4: JumpSign(back: .daCapo, until: .end)])
        XCTAssertEqual(PlayOrder.bars(Array(1...4), repeats: repeats), [1, 2, 3, 4, 1, 2])
    }

    /// The band convention: a repeat already taken is played straight
    /// through after the jump.
    func testARepeatIsNotTakenAgainAfterTheJump() {
        let repeats = marks(fine: 3, jumps: [4: JumpSign(back: .daCapo, until: .fine)], ends: [2])
        XCTAssertEqual(PlayOrder.bars(Array(1...4), repeats: repeats), [1, 2, 1, 2, 3, 4, 1, 2, 3])
    }

    /// And of its endings only the last is played: the 1st ending leads back
    /// into a repeat that is not taken now.
    func testOnlyTheLastEndingIsPlayedAfterTheJump() {
        let repeats = marks(segno: 2, fine: 5, jumps: [6: JumpSign(back: .dalSegno, until: .fine)],
                            starts: [2], ends: [3], endings: [3: [1], 4: [2]])
        XCTAssertEqual(PlayOrder.bars(Array(1...6), repeats: repeats), [1, 2, 3, 2, 4, 5, 6, 2, 4, 5])
    }

    /// A repeat inside the coda has never been played, so it is taken.
    func testARepeatInTheCodaIsTaken() {
        let repeats = marks(segno: 1, coda: 4, toCoda: 2, jumps: [3: JumpSign(back: .dalSegno, until: .coda)],
                            starts: [4], ends: [5])
        XCTAssertEqual(PlayOrder.bars(Array(1...5), repeats: repeats), [1, 2, 3, 1, 2, 4, 5, 4, 5])
    }

    /// A D.S. whose sign the reader did not find is not guessed at. Going to
    /// the top would play bars the band does not play.
    func testADSWithNoSignIsNotTaken() {
        let repeats = marks(jumps: [4: JumpSign(back: .dalSegno, until: .end)])
        XCTAssertEqual(PlayOrder.bars(Array(1...4), repeats: repeats), [1, 2, 3, 4])
    }

    /// Al Coda with no "To Coda" read: the return pass plays on past the jump
    /// into the coda, which is where it ends up either way.
    func testAlCodaWithNoToCodaPlaysOnIntoTheCoda() {
        let repeats = marks(segno: 2, coda: 5, jumps: [4: JumpSign(back: .dalSegno, until: .coda)])
        XCTAssertEqual(PlayOrder.bars(Array(1...6), repeats: repeats), [1, 2, 3, 4, 2, 3, 4, 5, 6])
    }

    func testTheWordsAreReadWhateverTheSpacing() {
        XCTAssertEqual(RepeatMarks.jump(named: "D.S.\tal\tCoda"), .sign(JumpSign(back: .dalSegno, until: .coda)))
        XCTAssertEqual(RepeatMarks.jump(named: "D. C. al Fine"), .sign(JumpSign(back: .daCapo, until: .fine)))
        XCTAssertEqual(RepeatMarks.jump(named: "Dal Segno al Coda"), .sign(JumpSign(back: .dalSegno, until: .coda)))
        XCTAssertEqual(RepeatMarks.jump(named: "Da Capo"), .sign(JumpSign(back: .daCapo, until: .end)))
        XCTAssertEqual(RepeatMarks.jump(named: "D.S."), .sign(JumpSign(back: .dalSegno, until: .end)))
        XCTAssertEqual(RepeatMarks.jump(named: "To\tCoda"), .toCoda)
        XCTAssertEqual(RepeatMarks.jump(named: "Fine"), .fine)
        XCTAssertNil(RepeatMarks.jump(named: "Finale"))
        XCTAssertNil(RepeatMarks.jump(named: "Horn in F"))
    }

    // MARK: - The page

    private func fixture(_ name: String) throws -> Score {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "pdf"),
                                "\(name).pdf is not in the test bundle")
        return try ScoreImporter.readOrThrow(url: url)
    }

    func testTheDSFixtureReadsEveryMarkAndPlaysAsABandDoes() throws {
        let score = try fixture("jumps-ds")
        XCTAssertEqual(score.events.map(\.measure).max(), 10)
        XCTAssertEqual(score.suspectMeasures, [])
        XCTAssertEqual(score.repeats.segno, 3)
        XCTAssertEqual(score.repeats.toCoda, 6)
        XCTAssertEqual(score.repeats.coda, 9)
        XCTAssertNil(score.repeats.fine)
        XCTAssertEqual(score.repeats.jumps, [8: JumpSign(back: .dalSegno, until: .coda)])
        XCTAssertEqual(score.playOrder, Array(1...8) + Array(3...6) + [9, 10])
        // The title says "D.S. al Coda" too, far over the staff, and is not read.
        XCTAssertEqual(score.repeats.jumps.count, 1)
    }

    func testTheDCFixtureReadsEveryMarkAndPlaysAsABandDoes() throws {
        let score = try fixture("jumps-dc")
        XCTAssertEqual(score.events.map(\.measure).max(), 6)
        XCTAssertEqual(score.suspectMeasures, [])
        XCTAssertEqual(score.repeats.fine, 4)
        XCTAssertNil(score.repeats.segno)
        XCTAssertEqual(score.repeats.jumps, [6: JumpSign(back: .daCapo, until: .fine)])
        XCTAssertEqual(score.playOrder, Array(1...6) + Array(1...4))
    }

    /// Heard, not just ordered: the D.S. fixture's bars each hold one pitch
    /// run, so the timeline's notes say which bar is playing.
    @MainActor
    func testThePartScreenPlaysTheJumpAndSaysSo() throws {
        let model = PartModel()
        model.adopt(try fixture("jumps-ds"))
        let timeline = try XCTUnwrap(model.prepare(bpm: 120, instrument: .mellophone))
        XCTAssertEqual(timeline.measures.map(\.number), Array(1...8) + Array(3...6) + [9, 10])
        let firsts = timeline.measures.indices.map { index in
            timeline.entries.first { $0.start >= timeline.measures[index].start - 1e-9 }?.event.writtenName
        }
        XCTAssertEqual(firsts, ["C4", "G4", "E4", "F4", "G4", "A4", "B4", "C5", "E4", "F4", "G4", "A4", "D5", "E5"])
        XCTAssertEqual(model.repeatNote, "Takes the D.S. al Coda: 1 to 8, 3 to 6, 9 to 10.")
        XCTAssertEqual(model.rows.map(\.label), (1...10).map(String.init), "the bar list stays the page")
    }

    /// The whole part is the whole performance. Cut "to the next time bar 6
    /// comes up", the D.C. al Fine fixture played 1 to 6 and never went back,
    /// because after the D.C. the part ends at bar 4 and bar 6 never comes
    /// round again. Found in the web port's chart screen.
    @MainActor
    func testTheWholePartTakesADCThatEndsBeforeTheLastPrintedBar() throws {
        let model = PartModel()
        model.adopt(try fixture("jumps-dc"))
        XCTAssertTrue(model.isWholePart)
        let timeline = try XCTUnwrap(model.prepare(bpm: 120, instrument: .mellophone))
        XCTAssertEqual(timeline.measures.map(\.number), Array(1...6) + Array(1...4))
        XCTAssertEqual(model.repeatNote, "Takes the D.C. al Fine: 1 to 6, 1 to 4.")
        // A range that stops short of the last bar is still cut as before.
        model.end(at: 5)
        XCTAssertEqual(model.prepare(bpm: 120, instrument: .mellophone)?.measures.map(\.number), Array(1...5))
    }
}
