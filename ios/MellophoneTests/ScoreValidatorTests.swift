import XCTest
import CoreGraphics
@testable import Mellophone

/// The reader is only as trustworthy as this check. It is the same idea as
/// `verifyFingerings()` re-checking the fingering derivation in the browser on
/// every load, and as `check-instruments.js` refusing to run when the stored
/// table disagrees: a measure whose durations do not sum to its time signature
/// is a measure the reader got wrong, and it must say so rather than play a
/// guess.
///
/// The negative controls are the point. A validator nobody has watched fail is
/// not a validator, which is the lesson `ScalePitchTests` was built on.
///
/// Same frame as the other ScoreBuilder tests: PDF y counts UPWARD and
/// `lineYs[0]` is the bottom line. Measures are numbered from 1, as the
/// engraver numbers them.
final class ScoreValidatorTests: XCTestCase {

    private let lineYs = [360.52, 365.48, 370.44, 375.40, 380.36]
    private let halfSpace = 2.48

    private func y(step: Double) -> Double { lineYs[0] + step * halfSpace }

    private func clef() -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE050, x: 46, y: y(step: 2), size: 19.84, font: "Leland")
    }
    /// A stacked 4 over 4: the upper digit is the beats.
    private func timeSig44(x: Double = 70) -> [PlacedGlyph] {
        [PlacedGlyph(scalar: 0xE084, x: x, y: y(step: 6), size: 19.84, font: "Leland"),
         PlacedGlyph(scalar: 0xE084, x: x, y: y(step: 2), size: 19.84, font: "Leland")]
    }
    private func timeSig24(x: Double) -> [PlacedGlyph] {
        [PlacedGlyph(scalar: 0xE082, x: x, y: y(step: 6), size: 19.84, font: "Leland"),
         PlacedGlyph(scalar: 0xE084, x: x, y: y(step: 2), size: 19.84, font: "Leland")]
    }
    private func quarters(_ xs: [Double]) -> [PlacedGlyph] {
        xs.map { PlacedGlyph(scalar: 0xE0A4, x: $0, y: y(step: 4), size: 19.84, font: "Leland") }
    }
    private func barline(x: Double) -> PlacedPath {
        PlacedPath(vertices: [], filled: false,
                   bounds: CGRect(x: x, y: lineYs[0], width: 0, height: lineYs[4] - lineYs[0]))
    }
    private func build(_ glyphs: [PlacedGlyph], _ paths: [PlacedPath] = []) -> Score {
        let staff = lineYs.map {
            PlacedPath(vertices: [], filled: true,
                       bounds: CGRect(x: 42.5, y: $0 - 0.35, width: 510, height: 0.7))
        }
        return ScoreBuilder.build(pages: [PageGeometry(glyphs: [clef()] + glyphs,
                                                       paths: staff + paths)],
                                  font: MusicFontTable.forFont("Leland")!)
    }

    // MARK: - The check

    /// Four quarters in 4/4 sums, so nothing is flagged. Two full bars, because
    /// a lone bar is exempt as a possible pickup.
    func testCompleteMeasuresAreNotFlagged() {
        let score = build(timeSig44() + quarters([100, 120, 140, 160, 220, 240, 260, 280]),
                          [barline(x: 200), barline(x: 300)])
        XCTAssertTrue(score.suspectMeasures.isEmpty, "flagged \(score.suspectMeasures)")
        XCTAssertEqual(score.events.count, 8)
    }

    /// NEGATIVE CONTROL: three quarters in 4/4 does not sum, and must be caught.
    /// The short bar is in the MIDDLE, because a short first bar is a pickup and
    /// is exempt by design. See `testAPickupIsNotFlagged`.
    func testShortMeasureIsFlagged() {
        let score = build(timeSig44() + quarters([100, 120, 140, 160, 220, 240, 260, 320, 340, 360, 380]),
                          [barline(x: 200), barline(x: 300), barline(x: 400)])
        XCTAssertEqual(score.suspectMeasures, [2], "a three-beat measure in 4/4 must be flagged")
    }

    /// NEGATIVE CONTROL: five quarters in 4/4 must be caught too. A validator
    /// that only checks one direction misses every duration read as too short,
    /// which is the failure a missed beam produces.
    func testOverfullMeasureIsFlagged() {
        let score = build(timeSig44() + quarters([100, 120, 140, 160, 180, 220, 240, 260, 280]),
                          [barline(x: 200), barline(x: 300)])
        XCTAssertEqual(score.suspectMeasures, [1])
    }

    /// A good measure next to a bad one must not be flagged with it, or the flag
    /// tells Sam nothing about where to look.
    func testOnlyTheBadMeasureIsFlagged() {
        let score = build(timeSig44() + quarters([100, 120, 140, 160, 220, 240, 260, 320, 340, 360, 380]),
                          [barline(x: 200), barline(x: 300), barline(x: 400)])
        XCTAssertEqual(score.suspectMeasures, [2])
    }

    /// A short FIRST bar is a pickup, which is how music is written and not a
    /// reading error. A short last bar is its other half. Neither is flagged.
    func testAPickupIsNotFlagged() {
        let score = build(timeSig44() + quarters([100, 220, 240, 260, 280, 320]),
                          [barline(x: 200), barline(x: 300), barline(x: 400)])
        XCTAssertTrue(score.suspectMeasures.isEmpty, "flagged \(score.suspectMeasures)")
    }

    /// NEGATIVE CONTROL for the exemption: an OVERFULL first bar is not a
    /// pickup, it is a mistake, and the exemption must not swallow it.
    func testAnOverfullFirstMeasureIsStillFlagged() {
        let score = build(timeSig44() + quarters([100, 120, 140, 160, 180, 220, 240, 260, 280, 320]),
                          [barline(x: 200), barline(x: 300), barline(x: 400)])
        XCTAssertTrue(score.suspectMeasures.contains(1))
    }

    /// Each measure is checked against ITS OWN meter, not the score's first one.
    ///
    /// A meter change does not wait for a new system. PEAK mello.pdf changes to
    /// 2/4 and back to 4/4 inside one staff, and checking every bar against the
    /// opening 4/4 flagged 83 of its 256 measures where checking each against
    /// its own flags 30. This is that case in miniature: four quarters, then a
    /// 2/4 sign, then two quarters. Both bars are correct.
    func testAMeterChangePartWayAlongAStaffAppliesFromThere() {
        let score = build(timeSig44() + quarters([100, 120, 140, 160])
                          + timeSig24(x: 210) + quarters([240, 260])
                          + quarters([320, 340]),
                          [barline(x: 200), barline(x: 300), barline(x: 400)])
        XCTAssertEqual(score.timeSignature.beats, 4, "the score still reports its opening meter")
        XCTAssertTrue(score.suspectMeasures.isEmpty, "flagged \(score.suspectMeasures)")
    }

    /// The bottom number travels with each measure, because playback needs it
    /// and one number for the whole score is wrong the moment the meter moves
    /// between quarters and eighths.
    ///
    /// Four quarters in 4/4, then a 6/8 sign, then three quarter noteheads. In
    /// 6/8 the eighth gets the beat, so each of those is TWO beats and the bar
    /// sums to six. Played back, a quarter has to still be a quarter: without
    /// the unit the second bar would run at half speed.
    func testEachMeasureCarriesTheUnitItsBeatsAreCountedIn() {
        let sixEight = [PlacedGlyph(scalar: 0xE086, x: 210, y: y(step: 6), size: 19.84, font: "Leland"),
                        PlacedGlyph(scalar: 0xE088, x: 210, y: y(step: 2), size: 19.84, font: "Leland")]
        let score = build(timeSig44() + quarters([100, 120, 140, 160])
                          + sixEight + quarters([240, 260, 280])
                          + quarters([320, 340, 360]),
                          [barline(x: 200), barline(x: 300), barline(x: 400)])
        // Bars 1 to 3 hold the notes. The closing barline also opens a bar 4
        // with nothing in it, and it is given a unit like any other, so only
        // the bars that have music are pinned here.
        XCTAssertEqual([1, 2, 3].map { score.beatUnits[$0] }, [4, 8, 8])
        XCTAssertEqual(score.beatUnit(of: 2), 8)
        XCTAssertEqual(score.beatUnit(of: 99), 4, "an unknown bar takes the opening signature's")
        XCTAssertEqual(score.events.filter { $0.measure == 2 }.map(\.durationBeats), [2, 2, 2])
        XCTAssertTrue(score.suspectMeasures.isEmpty, "flagged \(score.suspectMeasures)")

        // And through to seconds: at 60 every one of these quarters is a second.
        let timeline = PartTimeline(score: score, voice: .line(0), measures: 1...3, bpm: 60)
        XCTAssertTrue(timeline.entries.allSatisfy { abs($0.duration - 1) < 1e-9 },
                      "durations: \(timeline.entries.map(\.duration))")
        XCTAssertEqual(timeline.duration, 10, accuracy: 1e-9)
    }

    /// Divisi is summed on the TOP voice only. An engraver writes one notehead
    /// where the parts briefly meet, so the lower voice is legitimately short
    /// there, and flagging that would make the validator cry wolf on a chart
    /// that is written correctly.
    func testAPartialDivisiDoesNotFlagTheMeasure() {
        let upper = quarters([100, 120, 140, 160])
        let lower = [100.0, 120].map {
            PlacedGlyph(scalar: 0xE0A4, x: $0, y: y(step: 2), size: 19.84, font: "Leland")
        }
        let score = build(timeSig44() + upper + lower + quarters([220, 240, 260, 280]),
                          [barline(x: 200), barline(x: 300)])
        XCTAssertEqual(score.voiceCount, 2)
        XCTAssertTrue(score.suspectMeasures.isEmpty, "flagged \(score.suspectMeasures)")
    }

    /// Unrecognised glyphs are reported rather than dropped, so a chart from an
    /// engraver we have no table for can say what beat it.
    func testUnknownSymbolsAreReported() {
        let odd = PlacedGlyph(scalar: 0xE999, x: 100, y: y(step: 4), size: 19.84, font: "Leland")
        XCTAssertTrue(build(timeSig44() + [odd]).unreadableSymbols.contains(0xE999))
    }

    /// Flagging does not repair. The events keep whatever was read, because
    /// issue #9 is the precedent that a wrong value taught confidently is worse
    /// than an admitted gap.
    func testAFlaggedMeasureKeepsItsEvents() {
        let score = build(timeSig44() + quarters([100, 120, 140, 160, 220, 240, 260, 320, 340, 360, 380]),
                          [barline(x: 200), barline(x: 300), barline(x: 400)])
        XCTAssertEqual(score.suspectMeasures, [2])
        XCTAssertEqual(score.events.filter { $0.measure == 2 }.count, 3)
        XCTAssertEqual(score.events.filter { $0.measure == 2 }.map(\.durationBeats), [1, 1, 1])
    }
}
