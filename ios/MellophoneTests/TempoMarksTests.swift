import XCTest
@testable import Mellophone

/// The tempo mark finder against glyph lines built by hand (#41).
///
/// Hand-built, said once: each line here is a row of glyphs typed in, with the
/// fonts and spacing measured off Sam's charts and the fixture. What is real is
/// in `ChartReaderTrapsTests`, which reads marks off engraved PDFs. These are
/// the shapes that must NOT come back as a tempo, which no chart in the repo
/// happens to print.
final class TempoMarksTests: XCTestCase {

    /// Glyphs left to right from `x`, `advance` points apart, on one baseline.
    private func line(_ glyphs: [(UInt32, String)], from x: Double = 100, advance: Double = 4,
                      y: Double = 600) -> [PlacedGlyph] {
        glyphs.enumerated().map { index, glyph in
            PlacedGlyph(scalar: glyph.0, x: x + Double(index) * advance, y: y, size: 12, font: glyph.1)
        }
    }

    private func text(_ string: String, font: String = "Quicksand-SemiBold") -> [(UInt32, String)] {
        string.unicodeScalars.map { ($0.value, font) }
    }

    private func marks(_ glyphs: [PlacedGlyph]) -> [TempoMark] {
        TempoMarks.find(on: PageGeometry(glyphs: glyphs, paths: []))
    }

    func testPEAKsShapeIsRead() {
        let found = marks(line([(0x71, "OpusTextStd")] + text(" = 120")))
        XCTAssertEqual(found.map(\.printed), [120])
        XCTAssertEqual(found.first?.noteQuarters, 1)
    }

    func testFloridasShapeIsRead() {
        let found = marks(line([(0xECA5, "LelandText")] + text("\t=\t158", font: "Edwin-Bold")))
        XCTAssertEqual(found.map(\.printed), [158])
    }

    func testFastPlusReadsAsItsNumber() {
        XCTAssertEqual(marks(line([(0x71, "OpusTextStd")] + text(" = 160+"))).map(\.printed), [160])
    }

    /// A "q" in a text font is the letter q.
    func testTheLetterQIsNotAQuarterNote() {
        XCTAssertTrue(marks(line(text("q = 120"))).isEmpty)
    }

    /// "♩ = ♩." changes what gets the beat and prints no number.
    func testAMetricModulationIsNotATempo() {
        XCTAssertTrue(marks(line([(0xECA5, "LelandText")] + text(" = ") + [(0xECA5, "LelandText"), (0xECB7, "LelandText")])).isEmpty)
    }

    func testANumberNoTempoIsPlayedAtIsNotATempo() {
        XCTAssertTrue(marks(line([(0xECA5, "LelandText")] + text(" = 1200"))).isEmpty)
        XCTAssertTrue(marks(line([(0xECA5, "LelandText")] + text(" = 8"))).isEmpty)
    }

    /// A bar number printed before the mark, as on PEAK's "102 ♩ = 132", is
    /// not part of it, and digits on the next line down are not either.
    func testDigitsAroundTheMarkAreNotItsNumber() {
        let barNumber = line(text("102", font: "Quicksand-Italic"), from: 80)
        let mark = line([(0x71, "OpusTextStd")] + text(" = 132"), from: 100)
        let below = line(text("99"), from: 120, y: 590)
        XCTAssertEqual(marks(barNumber + mark + below).map(\.printed), [132])
    }

    /// An "=" and a number a word's width away belong to something else.
    func testAnEqualsSignTooFarAwayIsNotTheMarks() {
        let note = line([(0xECA5, "LelandText")])
        let far = line(text("= 120"), from: 140)
        XCTAssertTrue(marks(note + far).isEmpty)
    }
}
