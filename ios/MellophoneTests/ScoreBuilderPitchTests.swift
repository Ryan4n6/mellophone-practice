import XCTest
import CoreGraphics
@testable import Mellophone

/// Pitch reading, tested against hand-built geometry rather than a PDF, so the
/// staff coordinates are exact and a failure points at the music logic rather
/// than at the parser.
///
/// **The frame.** PDF user space has y increasing UPWARD, so `lineYs[0]` is the
/// BOTTOM line and a larger step is a higher pitch. The line positions below are
/// the real ones from page 1 of the MuseScore chart in issue #19, and under a
/// treble clef they are E4, G4, B4, D5, F5 from `lineYs[0]` up. The first test
/// is the one that fails if anyone flips that frame back: a whole part read
/// upside down still sounds like music, which is why it needs its own gate.
final class ScoreBuilderPitchTests: XCTestCase {

    private let lineYs = [360.52, 365.48, 370.44, 375.40, 380.36]
    private let halfSpace = 2.48
    private var leland: MusicFontTable { MusicFontTable.forFont("Leland")! }

    /// y of a step above the bottom line: 0 is the E4 line, 8 the F5 line.
    private func y(step: Double) -> Double { lineYs[0] + step * halfSpace }

    private func head(x: Double, step: Double, scalar: UInt32 = 0xE0A4) -> PlacedGlyph {
        PlacedGlyph(scalar: scalar, x: x, y: y(step: step), size: 19.84, font: "Leland")
    }

    /// The treble clef's origin sits on G4, two steps above the bottom line.
    /// Measured at exactly 2.00 in both engravers, which is what anchors pitch.
    private func clef(x: Double = 46.24) -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE050, x: x, y: y(step: 2), size: 19.84, font: "Leland")
    }

    private func accidental(_ scalar: UInt32, x: Double, step: Double) -> PlacedGlyph {
        PlacedGlyph(scalar: scalar, x: x, y: y(step: step), size: 19.84, font: "Leland")
    }
    private func flat(x: Double, step: Double) -> PlacedGlyph { accidental(0xE260, x: x, step: step) }
    private func sharp(x: Double, step: Double) -> PlacedGlyph { accidental(0xE262, x: x, step: step) }
    private func natural(x: Double, step: Double) -> PlacedGlyph { accidental(0xE261, x: x, step: step) }

    private func digit(_ value: Int, x: Double, step: Double) -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE080 + UInt32(value), x: x, y: y(step: step), size: 19.84, font: "Leland")
    }

    /// The five staff lines, drawn the way MuseScore draws them.
    private func staffPaths() -> [PlacedPath] {
        lineYs.map {
            PlacedPath(vertices: [], filled: true,
                       bounds: CGRect(x: 42.5, y: $0 - 0.35, width: 510, height: 0.7))
        }
    }

    /// A barline spans the staff exactly, both ends, which is what tells it from
    /// a stem.
    private func barline(x: Double) -> PlacedPath {
        PlacedPath(vertices: [], filled: false,
                   bounds: CGRect(x: x, y: lineYs[0], width: 0, height: lineYs[4] - lineYs[0]))
    }

    private func score(_ glyphs: [PlacedGlyph], _ paths: [PlacedPath] = []) -> Score {
        ScoreBuilder.build(pages: [PageGeometry(glyphs: glyphs, paths: staffPaths() + paths)],
                           font: leland)
    }

    // MARK: - The frame

    func testNotesOnLinesReadUpwardFromE4() {
        let heads = zip([100.0, 120, 140, 160, 180], [0.0, 2, 4, 6, 8]).map { head(x: $0, step: $1) }
        XCTAssertEqual(score([clef()] + heads).events.map(\.writtenName),
                       ["E4", "G4", "B4", "D5", "F5"])
    }

    func testNotesOnSpacesReadFACE() {
        let heads = zip([100.0, 120, 140, 160], [1.0, 3, 5, 7]).map { head(x: $0, step: $1) }
        XCTAssertEqual(score([clef()] + heads).events.map(\.writtenName),
                       ["F4", "A4", "C5", "E5"])
    }

    // MARK: - Key signature

    /// One flat in the key signature makes every B a Bb, including the B in a
    /// different octave, which is the case a naive implementation gets wrong.
    func testKeySignatureAppliesToEveryOctave() {
        let result = score([clef(), flat(x: 63.90, step: 4),
                            head(x: 100, step: 4), head(x: 120, step: 11)])
        XCTAssertEqual(result.keySignature, -1)
        XCTAssertEqual(result.events.compactMap { $0.note?.name }, ["Bb4", "Bb5"])
    }

    /// The Florida bottom system, verbatim: a key flat on the B line followed by
    /// a courtesy flat on the SAME line. A second key flat would be on the E
    /// line, so the run ends at the first one and the second is inline. Getting
    /// this wrong reads the part a whole key out.
    func testKeySignatureRunStopsWhenTheOrderBreaks() {
        let result = score([clef(), flat(x: 63.90, step: 4), flat(x: 75.86, step: 4),
                            head(x: 81.13, step: 4), head(x: 81.13, step: 2)])
        XCTAssertEqual(result.keySignature, -1, "the second flat is a courtesy accidental")
        XCTAssertEqual(result.events.map(\.writtenName), ["Bb4", "G4"])
    }

    /// The PEAK head, verbatim: four flats at the B, E, A and D positions, then
    /// a stacked 4 over 4. Both halves of a head read at once, because that is
    /// how they actually arrive.
    func testFourFlatsAndAStackedTimeSignatureReadTogether() {
        let flats = [flat(x: 72.12, step: 4), flat(x: 77.30, step: 7),
                     flat(x: 82.48, step: 3), flat(x: 87.66, step: 6)]
        let result = score([clef(x: 56)] + flats
                           + [digit(4, x: 96.16, step: 6.09), digit(4, x: 96.16, step: 2.04),
                              head(x: 158.34, step: 6)])
        XCTAssertEqual(result.keySignature, -4)
        XCTAssertEqual(result.timeSignature.beats, 4)
        XCTAssertEqual(result.timeSignature.unit, 4)
        // Db, not D: the fourth flat is on the D line, so a bare notehead there
        // is already flat before any inline accidental is considered.
        XCTAssertEqual(result.events.map(\.writtenName), ["Db5"])
    }

    /// A 2 over 4, to prove the upper digit is the beats and not just that both
    /// digits happened to be 4.
    func testUpperDigitIsTheBeats() {
        let result = score([clef(x: 71.04), flat(x: 88.70, step: 4),
                            digit(2, x: 98.06, step: 5.95), digit(4, x: 97.41, step: 2.01)])
        XCTAssertEqual(result.timeSignature.beats, 2)
        XCTAssertEqual(result.timeSignature.unit, 4)
    }

    /// The trap the whole qualification exists for. On PEAK mello.pdf the digit
    /// glyphs appear 35 times as measure numbers and multi-measure rest counts
    /// against 8 real time signature digits, above the staff at step 11.10 on a
    /// notehead's x. Reading one as a meter makes every measure fail the sum
    /// check, which turns the validator from signal into noise.
    func testDigitsOutsideTheStaffAreNotATimeSignature() {
        let result = score([clef(), digit(2, x: 162.66, step: 11.10),
                            digit(3, x: 162.66, step: 13.5), head(x: 200, step: 4)])
        XCTAssertEqual(result.timeSignature.beats, 4, "a measure number is not a meter")
        XCTAssertEqual(result.timeSignature.unit, 4)
    }

    // MARK: - Inline accidentals

    /// An inline accidental holds for the rest of its measure and then stops.
    ///
    /// The written pitch is G#4, which NoteData does not hold: the table stores
    /// five sharps and spells everything else flat. G#4 is comfortably inside
    /// the horn's range and is played 2+3, so it must resolve to the Ab4 row
    /// rather than fall through to "out of range" and be silenced. The page's
    /// own spelling survives on `writtenName`.
    func testInlineAccidentalPersistsToTheBarlineAndNoFurther() {
        let result = score([clef(), sharp(x: 95, step: 2), head(x: 100, step: 2),
                            head(x: 120, step: 2), head(x: 170, step: 2)],
                           [barline(x: 150)])
        XCTAssertEqual(result.events.compactMap { $0.note?.name }, ["Ab4", "Ab4", "G4"])
        XCTAssertEqual(result.events.map(\.writtenName), ["G#4", "G#4", "G4"])
        XCTAssertEqual(result.events.map(\.measure), [1, 1, 2])
    }

    /// Florida page 1 system 1, verbatim: a sharp on the lower note of a chord
    /// and a natural on the upper, the natural cancelling the key flat. Each
    /// accidental has to find its own notehead by staff position, not by being
    /// the nearest thing to the left.
    func testTwoAccidentalsOnOneChordEachFindTheirOwnNote() {
        let result = score([clef(), flat(x: 63.90, step: 4),
                            sharp(x: 236.73, step: 2), natural(x: 242.66, step: 4),
                            head(x: 247.29, step: 4), head(x: 247.29, step: 2)])
        XCTAssertEqual(result.events.map(\.writtenName), ["B4", "G#4"])
        XCTAssertEqual(result.events.compactMap { $0.note?.name }, ["B4", "Ab4"])
    }

    // MARK: - Voices

    /// Two noteheads at the same x are one chord, and on a horn part that is
    /// divisi. The Florida chart in issue #19 is written this way throughout.
    /// Voice 0 is the HIGHER note, which in this frame is the LARGER y.
    func testStackedNoteheadsBecomeTwoVoices() {
        let result = score([clef(), head(x: 100, step: 5), head(x: 100, step: 3)])
        XCTAssertEqual(result.voiceCount, 2)
        XCTAssertEqual(result.events.filter { $0.voice == 0 }.map(\.writtenName), ["C5"])
        XCTAssertEqual(result.events.filter { $0.voice == 1 }.map(\.writtenName), ["A4"])
    }

    // MARK: - Range

    /// A pitch above C6 is outside the instrument's range, so no row of NoteData
    /// can hold it. It must NOT collapse into a rest: an event that keeps its
    /// duration and reports its name is honest, silence is not.
    func testOutOfRangeNoteIsKeptAndNamedRatherThanSilenced() {
        // Eighteen steps above the bottom E4 line is B6, well past C6.
        let result = score([clef(), head(x: 100, step: 18)])
        XCTAssertEqual(result.events.count, 1)
        XCTAssertNil(result.events[0].note)
        XCTAssertFalse(result.events[0].isRest, "an out of range note is not a rest")
        XCTAssertEqual(result.events[0].outOfRangeName, "B6")
        XCTAssertEqual(result.events[0].durationBeats, 1, accuracy: 0.001,
                       "it keeps its duration or the bar plays short")
    }

    /// The negative control for the range test: one step lower is A6, still out
    /// of range, and two octaves lower is B4, which is not. A range check that
    /// rejected everything would pass the test above.
    func testAPitchInsideTheRangeIsNotReportedOutOfRange() {
        let result = score([clef(), head(x: 100, step: 4)])
        XCTAssertNil(result.events[0].outOfRangeName)
        XCTAssertEqual(result.events[0].note?.name, "B4")
    }
}
