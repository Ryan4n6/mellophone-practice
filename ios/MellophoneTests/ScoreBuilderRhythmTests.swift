import XCTest
import CoreGraphics
@testable import Mellophone

/// Rhythm is the half of this reader with no glyph to lean on. Whole and half
/// come off the notehead and flags are glyphs, but BEAMS ARE FILLED PATHS and a
/// multi-measure rest is two short vertical strokes with a number over them.
/// These tests build all of that as rectangles, because that is what it is in
/// the PDF.
///
/// Same frame as `ScoreBuilderPitchTests`: PDF y counts UPWARD, `lineYs[0]` is
/// the bottom line, and the positions are the real ones from the MuseScore
/// chart in issue #19. With no time signature glyphs the reader is in 4/4, so a
/// beat is a quarter throughout.
final class ScoreBuilderRhythmTests: XCTestCase {

    private let lineYs = [360.52, 365.48, 370.44, 375.40, 380.36]
    private let halfSpace = 2.48

    private func y(step: Double) -> Double { lineYs[0] + step * halfSpace }

    private func clef() -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE050, x: 46, y: y(step: 2), size: 19.84, font: "Leland")
    }
    private func head(x: Double, step: Double = 4, scalar: UInt32 = 0xE0A4) -> PlacedGlyph {
        PlacedGlyph(scalar: scalar, x: x, y: y(step: step), size: 19.84, font: "Leland")
    }

    /// An up stem: it starts at the notehead and runs upward, which in this
    /// frame is toward the LARGER y. Measured lengths are 5.2 to 11.6
    /// half-spaces, and it sits 2.5 across, the notehead's own width.
    private func stem(on notehead: PlacedGlyph, length: Double = 7) -> PlacedPath {
        PlacedPath(vertices: [], filled: false,
                   bounds: CGRect(x: notehead.x + 2.5 * halfSpace, y: notehead.y,
                                  width: 0, height: length * halfSpace))
    }

    /// A beam sits across the stem TIPS. Measured 0.6 to 2.6 half-spaces thick.
    private func beam(fromX: Double, toX: Double, atStep: Double) -> PlacedPath {
        PlacedPath(vertices: [], filled: true,
                   bounds: CGRect(x: fromX, y: y(step: atStep) - 0.75 * halfSpace,
                                  width: toX - fromX, height: 1.5 * halfSpace))
    }

    private func dot(after notehead: PlacedGlyph) -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE1E7, x: notehead.x + 3.3 * halfSpace,
                    y: notehead.y + halfSpace, size: 19.84, font: "Leland")
    }

    private func staffPaths() -> [PlacedPath] {
        lineYs.map {
            PlacedPath(vertices: [], filled: true,
                       bounds: CGRect(x: 42.5, y: $0 - 0.35, width: 510, height: 0.7))
        }
    }

    private func score(_ glyphs: [PlacedGlyph], _ paths: [PlacedPath] = []) -> Score {
        ScoreBuilder.build(pages: [PageGeometry(glyphs: [clef()] + glyphs,
                                                paths: staffPaths() + paths)],
                           font: MusicFontTable.forFont("Leland")!)
    }

    // MARK: - What the notehead alone can prove

    func testNoteheadShapeGivesWholeHalfAndQuarter() {
        let result = score([head(x: 100, scalar: 0xE0A2),
                            head(x: 200, scalar: 0xE0A3),
                            head(x: 300, scalar: 0xE0A4)])
        XCTAssertEqual(result.events.map(\.durationBeats), [4, 2, 1])
    }

    // MARK: - Flags and beams

    /// One flag is an eighth, two is a sixteenth. The flag glyph's origin sits
    /// about 5 half-spaces from its notehead, measured on all 35 in PEAK.
    func testFlagsShortenTheNote() {
        let first = head(x: 100), second = head(x: 150)
        let result = score([first,
                            PlacedGlyph(scalar: 0xE240, x: first.x + 2.5 * halfSpace,
                                        y: first.y + 5 * halfSpace, size: 19.84, font: "Leland"),
                            second,
                            PlacedGlyph(scalar: 0xE242, x: second.x + 2.5 * halfSpace,
                                        y: second.y + 5 * halfSpace, size: 19.84, font: "Leland")],
                           [stem(on: first), stem(on: second)])
        XCTAssertEqual(result.events.map(\.durationBeats), [0.5, 0.25])
    }

    /// One beam spanning two stems makes both eighths. This is the case that
    /// cannot be read from glyphs at all, because a beam has no codepoint.
    func testOneBeamMakesBothNotesEighths() {
        let a = head(x: 100), b = head(x: 120)
        let beamY = 4.0 + 7.0
        let result = score([a, b],
                           [stem(on: a), stem(on: b),
                            beam(fromX: a.x + 2.5 * halfSpace, toX: b.x + 2.5 * halfSpace,
                                 atStep: beamY)])
        XCTAssertEqual(result.events.map(\.durationBeats), [0.5, 0.5])
    }

    /// Two stacked beams make sixteenths, and the count of beams is the only
    /// thing that distinguishes them.
    func testTwoStackedBeamsMakeSixteenths() {
        let a = head(x: 100), b = head(x: 120)
        let result = score([a, b],
                           [stem(on: a), stem(on: b),
                            beam(fromX: a.x + 2.5 * halfSpace, toX: b.x + 2.5 * halfSpace, atStep: 11),
                            beam(fromX: a.x + 2.5 * halfSpace, toX: b.x + 2.5 * halfSpace, atStep: 9.4)])
        XCTAssertEqual(result.events.map(\.durationBeats), [0.25, 0.25])
    }

    // MARK: - Beams as the shapes they are (#29)

    /// A beam the way MuseScore draws it: a filled four cornered slab with
    /// upright ends, one half-space thick, its line running from `fromStep` at
    /// the left end to `toStep` at the right. The corners are given, which is
    /// what lets the reader follow the slope instead of guessing from the box.
    private func slab(fromX: Double, toX: Double, fromStep: Double, toStep: Double) -> PlacedPath {
        let left = y(step: fromStep), right = y(step: toStep), half = 0.5 * halfSpace
        let corners = [CGPoint(x: fromX, y: left - half), CGPoint(x: toX, y: right - half),
                       CGPoint(x: toX, y: right + half), CGPoint(x: fromX, y: left + half),
                       CGPoint(x: fromX, y: left - half)]
        let low = min(left, right) - half, high = max(left, right) + half
        return PlacedPath(vertices: corners, filled: true,
                          bounds: CGRect(x: fromX, y: low, width: toX - fromX, height: high - low))
    }

    /// Four eighths under one beam, climbing. This is the figure that read as
    /// four quarters: the beam is 18 half-spaces wide, past the 15 that is
    /// taken on sight, and its box is two and a half times its thickness.
    /// Positions follow bar 13 of the sample chart.
    func testABeamAcrossFourEighthsIsStillABeam() {
        let heads = [head(x: 100, step: 4), head(x: 115, step: 5),
                     head(x: 130, step: 6), head(x: 145, step: 7)]
        // The beam's line climbs from step 11 to 12.5, and every stem ends on it.
        let stems = zip(heads, [7.0, 6.5, 6.0, 5.5]).map { stem(on: $0, length: $1) }
        let beam = slab(fromX: 100 + 2.5 * halfSpace, toX: 145 + 2.5 * halfSpace,
                        fromStep: 11, toStep: 12.5)
        XCTAssertGreaterThan(Double(beam.bounds.width) / halfSpace, 15, "the test is not testing a wide beam")
        let result = score(heads, stems + [beam])
        XCTAssertEqual(result.events.map(\.durationBeats), [0.5, 0.5, 0.5, 0.5])
    }

    /// A steep beam over two notes. Its BOX is four half-spaces tall, past the
    /// 2.6 a beam may be thick, and the beam itself is one. Thickness is the
    /// height of the slab's end, not of the box around its slope.
    func testASteepBeamIsJudgedByItsThicknessNotItsBox() {
        let first = head(x: 100, step: 2), second = head(x: 115, step: 6)
        let stems = [stem(on: first, length: 8), stem(on: second, length: 7)]
        let beam = slab(fromX: 100 + 2.5 * halfSpace, toX: 115 + 2.5 * halfSpace,
                        fromStep: 10, toStep: 13)
        XCTAssertGreaterThan(Double(beam.bounds.height) / halfSpace, 2.6, "the test is not testing a steep beam")
        let result = score([first, second], stems + [beam])
        XCTAssertEqual(result.events.map(\.durationBeats), [0.5, 0.5])
    }

    /// The other half of the same rule. A slab just as wide that reaches only
    /// ONE note's stem is not a beam, whatever it is, and the note under its
    /// end stays a quarter. This is what keeps a multi-measure rest's H-bar,
    /// 20 to 66 wide, from shortening a note beside it.
    func testAWideSlabThatJoinsOnlyOneNoteIsNotABeam() {
        let only = head(x: 100, step: 4)
        let bar = slab(fromX: 100 + 2.5 * halfSpace, toX: 145 + 2.5 * halfSpace,
                       fromStep: 11, toStep: 11)
        let result = score([only], [stem(on: only, length: 7), bar])
        XCTAssertEqual(result.events.map(\.durationBeats), [1.0])
    }

    /// A note carries flags or beams, never both. Counting both would turn a
    /// beamed sixteenth into a sixty-fourth.
    func testABeamedNoteDoesNotAlsoCountItsFlag() {
        let a = head(x: 100), b = head(x: 120)
        let result = score([a, b,
                            PlacedGlyph(scalar: 0xE240, x: a.x + 2.5 * halfSpace,
                                        y: a.y + 5 * halfSpace, size: 19.84, font: "Leland")],
                           [stem(on: a), stem(on: b),
                            beam(fromX: a.x + 2.5 * halfSpace, toX: b.x + 2.5 * halfSpace, atStep: 11)])
        XCTAssertEqual(result.events.map(\.durationBeats), [0.5, 0.5])
    }

    // MARK: - Dots

    func testAugmentationDotExtendsTheNote() {
        let note = head(x: 100, scalar: 0xE0A3)
        let result = score([note, dot(after: note)])
        XCTAssertEqual(result.events[0].durationBeats, 3.0, accuracy: 0.001)
    }

    /// The negative control for the dot, and the reason the Opus table had to be
    /// remeasured. A staccato also rides a notehead, but it sits directly over
    /// or under it rather than to the right, and it must not lengthen anything.
    /// Reading Opus's staccato as an augmentation dot lengthened 64 notes by
    /// half.
    func testAStaccatoDoesNotLengthenTheNote() {
        let note = head(x: 100, scalar: 0xE0A3)
        let staccato = PlacedGlyph(scalar: 0xE4A2, x: note.x + 0.88 * halfSpace,
                                   y: note.y - 2 * halfSpace, size: 19.84, font: "Leland")
        XCTAssertEqual(score([note, staccato]).events[0].durationBeats, 2.0, accuracy: 0.001)
    }

    // MARK: - Rests

    /// A rest occupies time and produces an event with no note, because "how
    /// long do I sit out before I come in" is half the value of hearing a
    /// marching part at all.
    func testRestsProduceSilentEventsThatOccupyTime() {
        let result = score([head(x: 100),
                            PlacedGlyph(scalar: 0xE4E5, x: 140, y: y(step: 4),
                                        size: 19.84, font: "Leland"),
                            head(x: 180)])
        XCTAssertEqual(result.events.count, 3)
        XCTAssertTrue(result.events[1].isRest)
        XCTAssertNil(result.events[1].note)
        XCTAssertEqual(result.events[2].onsetBeats, 2.0, accuracy: 0.001)
    }

    /// A multi-measure rest is one H-bar standing for many bars, and counting it
    /// as one is what made every measure number the reader reported too low: on
    /// the MuseScore chart it ended at 36 where the engraver prints 36 at the
    /// START of the last system, exactly the five bars its opening six-bar rest
    /// swallowed.
    ///
    /// The bar itself is stroked by MuseScore and filled by Sibelius, so the
    /// thing to key on is the pair of END CAPS, which span steps 2 to 6 in both.
    /// The count is printed centred above it in the music font.
    func testAMultiMeasureRestCountsEveryBarItStandsFor() throws {
        let caps = [116.09, 166.42].map {
            PlacedPath(vertices: [], filled: false,
                       bounds: CGRect(x: $0, y: y(step: 2), width: 0, height: 4 * halfSpace))
        }
        let bar = PlacedPath(vertices: [], filled: false,
                             bounds: CGRect(x: 116.09, y: y(step: 4), width: 50.33, height: 0))
        let count = PlacedGlyph(scalar: 0xE086, x: 141.26, y: y(step: 11),
                                size: 19.84, font: "Leland")
        let result = score([count, head(x: 300)], caps + [bar])

        let rests = result.events.filter(\.isRest)
        XCTAssertEqual(rests.count, 6, "six bars of rest, not one")
        XCTAssertEqual(rests.map(\.measure), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(result.events.last?.measure, 6,
                       "the note after the rest is in the sixth bar, not the second")
        XCTAssertEqual(try XCTUnwrap(result.events.last).onsetBeats, 24.0, accuracy: 0.001,
                       "six bars of 4/4 have gone by")
    }

    /// A digit above the staff is a measure number far more often than it is a
    /// rest count, so it only counts when it sits over an H-bar. Without the
    /// end caps there is no rest at all.
    func testADigitAboveTheStaffWithNoBarUnderItIsNotARestCount() {
        let count = PlacedGlyph(scalar: 0xE086, x: 141.26, y: y(step: 11),
                                size: 19.84, font: "Leland")
        let result = score([count, head(x: 300)])
        XCTAssertTrue(result.events.filter(\.isRest).isEmpty)
        XCTAssertEqual(result.events.first?.measure, 1)
    }

    // MARK: - Onsets

    /// Onsets accumulate across everything that occupies time, in x order. A
    /// rest left out of the timeline makes every note after it start early.
    func testOnsetsAccumulateAcrossNotesAndRests() {
        let result = score([head(x: 100, scalar: 0xE0A3),
                            PlacedGlyph(scalar: 0xE4E5, x: 160, y: y(step: 4),
                                        size: 19.84, font: "Leland"),
                            head(x: 220, scalar: 0xE0A4)])
        XCTAssertEqual(result.events.map(\.onsetBeats), [0, 2, 3])
        XCTAssertEqual(result.events.map(\.durationBeats), [2, 1, 1])
    }
}
