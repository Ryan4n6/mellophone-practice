import XCTest
import CoreGraphics
import UIKit
@testable import Mellophone

/// The reader is tested against a PDF this test draws itself, so the expected
/// geometry is known exactly rather than measured off somebody's export.
///
/// Nothing here is musical, on purpose. PDFGlyphReader must not know what a
/// notehead is: a staff line, a stem, a beam, a barline and a slur are all just
/// paths, and telling them apart is a music question that belongs downstream.
/// That is also why the reader does not filter by font. Filtering here would
/// make this file untestable without shipping a music font into the test bundle.
///
/// Distances are asserted rather than absolute coordinates. UIGraphicsPDFRenderer
/// draws through a flip, real engravers do not, and a test that pinned absolute
/// y would be pinning this test's own convention instead of the reader's
/// correctness. Absolute staff coordinates get pinned in ScoreBuilder's tests,
/// against hand-built geometry.
final class PDFGlyphReaderTests: XCTestCase {

    /// Two filled bars and two single characters, each at a known place.
    ///
    /// The characters are drawn as SEPARATE runs rather than one "AB" string
    /// because that is how engravers emit music: the charts in issue #19 give
    /// every glyph its own Td. It also keeps this test off the width tables,
    /// which are a fallback path and not what is under test here.
    private func makeTestPDF() throws -> CGPDFPage {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            ctx.beginPage()
            UIColor.black.setFill()
            // Thin and wide, like a staff line.
            UIRectFill(CGRect(x: 50, y: 100, width: 300, height: 1))
            // Thick and short, like a beam. 100 below the first, 10 to its right.
            UIRectFill(CGRect(x: 60, y: 200, width: 20, height: 8))

            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            NSAttributedString(string: "A", attributes: attrs).draw(at: CGPoint(x: 30, y: 40))
            NSAttributedString(string: "B", attributes: attrs).draw(at: CGPoint(x: 60, y: 90))
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let doc = try XCTUnwrap(CGPDFDocument(provider))
        return try XCTUnwrap(doc.page(at: 1))
    }

    func testFindsFilledPathsAndTheirShapes() throws {
        let geometry = PDFGlyphReader.read(page: try makeTestPDF())

        let wide = geometry.paths.filter { $0.filled && $0.bounds.width > 100 }
        XCTAssertEqual(wide.count, 1, "expected exactly one long thin bar")
        XCTAssertEqual(wide[0].bounds.width, 300, accuracy: 1.0)
        XCTAssertEqual(wide[0].bounds.height, 1, accuracy: 0.5)

        let thick = geometry.paths.filter { $0.filled && $0.bounds.height > 5 }
        XCTAssertEqual(thick.count, 1, "expected exactly one short thick bar")
        XCTAssertEqual(thick[0].bounds.width, 20, accuracy: 1.0)
        XCTAssertEqual(thick[0].bounds.height, 8, accuracy: 0.5)
    }

    /// The two bars were drawn with their origins 100 apart vertically and 10
    /// apart horizontally. Asserting the SEPARATION catches a scale error in the
    /// CTM, which is the failure that would otherwise put every note on the
    /// wrong line, while staying agnostic about which way is up.
    ///
    /// The centres are 103.5 apart, not 100: the bars are 1 and 8 tall, so half
    /// the height difference falls between their midpoints. An earlier version
    /// of this test asserted 100 and the reader returned 103.5, which was the
    /// test being wrong to the tenth of a point and the reader being right.
    func testPathPositionsAreRelatedCorrectly() throws {
        let geometry = PDFGlyphReader.read(page: try makeTestPDF())
        let wide = try XCTUnwrap(geometry.paths.first { $0.filled && $0.bounds.width > 100 })
        let thick = try XCTUnwrap(geometry.paths.first { $0.filled && $0.bounds.height > 5 })

        let expectedCentreGap = 100.0 + (8.0 - 1.0) / 2
        XCTAssertEqual(abs(wide.bounds.midY - thick.bounds.midY),
                       expectedCentreGap, accuracy: 0.5)
        // The edges nearest each other are exactly the origin distance apart.
        XCTAssertEqual(abs(wide.bounds.maxY - thick.bounds.maxY), 100, accuracy: 0.5)
        XCTAssertEqual(thick.bounds.minX - wide.bounds.minX, 10, accuracy: 0.5)
    }

    func testFindsGlyphsAndDecodesThem() throws {
        let geometry = PDFGlyphReader.read(page: try makeTestPDF())
        XCTAssertEqual(geometry.glyphs.count, 2, "two characters were drawn")

        let decoded = geometry.glyphs
            .map { String(format: "U+%04X", $0.scalar) }
            .joined(separator: " ")
        let scalars = Set(geometry.glyphs.map(\.scalar))
        XCTAssertEqual(scalars.count, 2, "A and B must not decode to the same value: \(decoded)")
        XCTAssertEqual(scalars, [0x41, 0x42], "expected A and B, got \(decoded)")
    }

    /// The two characters were drawn 30 apart horizontally and 50 apart
    /// vertically. If Td accumulation is wrong they stack at one point, which is
    /// the silent failure that would make a whole system read as one chord.
    func testGlyphPositionsAreRelatedCorrectly() throws {
        let geometry = PDFGlyphReader.read(page: try makeTestPDF())
        let byX = geometry.glyphs.sorted { $0.x < $1.x }
        XCTAssertEqual(byX.count, 2)
        XCTAssertEqual(byX[1].x - byX[0].x, 30, accuracy: 2.0)
        XCTAssertEqual(abs(byX[1].y - byX[0].y), 50, accuracy: 2.0)
    }

    func testReportsTheFontEachGlyphWasDrawnIn() throws {
        let geometry = PDFGlyphReader.read(page: try makeTestPDF())
        XCTAssertFalse(geometry.glyphs.contains { $0.font.isEmpty },
                       "every glyph carries its BaseFont so the caller can pick a table")
        XCTAssertEqual(geometry.glyphs[0].size, 12, accuracy: 0.5)
    }

    /// A page with nothing on it comes back empty rather than crashing. A title
    /// page in a real chart is exactly this, and so is a page the scanner fails
    /// on, which is why the empty case has to be a normal result.
    func testEmptyPageYieldsEmptyGeometry() throws {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
            .pdfData { $0.beginPage() }
        let doc = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: data as CFData))))
        let geometry = PDFGlyphReader.read(page: try XCTUnwrap(doc.page(at: 1)))
        XCTAssertTrue(geometry.glyphs.isEmpty)
    }
}
