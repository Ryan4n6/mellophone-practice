import SwiftUI
import XCTest
@testable import Mellophone

/// The drawings on the instrument chip (#36).
///
/// What a test can say about a drawing is narrow, and this says only that:
/// each horn has a picture of its own, and each picture stays inside the
/// frame it is given. Whether a picture LOOKS like its horn was judged by
/// eye, rendered large and at the size it is used at, and is not tested.
final class BrassGlyphTests: XCTestCase {

    /// One picture per HORN. The euphonium is one horn read in two clefs
    /// (#72), so its two entries share the euphonium; every other pair of
    /// entries is a different horn and draws differently.
    func testEveryHornHasItsOwnPicture() {
        let horns = Instrument.allCases.filter { $0 != .euphoniumBass }
        let kinds = horns.map(\.glyph)
        XCTAssertEqual(Set(kinds).count, horns.count, "two instruments share a drawing: \(kinds)")
        XCTAssertEqual(Set(kinds), Set(BrassGlyph.Kind.allCases), "a drawing nobody uses")
        XCTAssertEqual(Instrument.trumpet.glyph, .trumpet)
        XCTAssertEqual(Instrument.mellophone.glyph, .mellophone)
        XCTAssertEqual(Instrument.frenchHorn.glyph, .frenchHorn)
        XCTAssertEqual(Instrument.euphonium.glyph, .euphonium)
        XCTAssertEqual(Instrument.euphoniumBass.glyph, .euphonium, "the same horn")
        XCTAssertEqual(Instrument.tuba.glyph, .tuba)
    }

    /// A tuba and a euphonium are the two that could be mistaken, both upright
    /// with the bell on top. What tells them apart is the bell: the tuba's is
    /// wider than the body under it, the euphonium's narrower.
    func testATubasBellIsWiderThanItsBody() {
        let frame = CGRect(x: 0, y: 0, width: 24, height: 17)
        func bellOverBody(_ kind: BrassGlyph.Kind) -> CGFloat {
            let parts = BrassGlyph.parts(for: kind, in: frame)
            // The body is the first part of both drawings, the bell the next.
            return parts[1].boundingRect.width / parts[0].boundingRect.width
        }
        XCTAssertGreaterThan(bellOverBody(.tuba), 1.1)
        XCTAssertLessThan(bellOverBody(.euphonium), 1.0)
    }

    /// Four names are not four pictures. The test above would pass if two
    /// kinds drew the same horn (#37), so this compares what is DRAWN: every
    /// pair of horns, in the chip's own frame, has to differ in its outline.
    func testNoTwoHornsAreDrawnTheSame() {
        let frame = CGRect(x: 0, y: 0, width: 24, height: 17)
        let kinds = BrassGlyph.Kind.allCases
        for (i, a) in kinds.enumerated() {
            for b in kinds[(i + 1)...] {
                XCTAssertNotEqual(BrassGlyph.parts(for: a, in: frame), BrassGlyph.parts(for: b, in: frame),
                                  "\(a) and \(b) are drawn the same")
            }
        }
    }

    /// A part drawn outside its box is cut off by the chip, or pushes the
    /// rest of the horn off centre.
    func testEveryPictureStaysInsideItsFrameAndFillsIt() {
        // The chip's frame, and one much wider than tall and much taller
        // than wide, since the fit is by the tighter side.
        for size in [CGSize(width: 24, height: 17), CGSize(width: 300, height: 40), CGSize(width: 40, height: 300)] {
            let frame = CGRect(origin: .zero, size: size)
            for kind in BrassGlyph.Kind.allCases {
                let parts = BrassGlyph.parts(for: kind, in: frame)
                XCTAssertGreaterThan(parts.count, 3, "\(kind) is hardly a drawing")
                let drawn = parts.reduce(CGRect.null) { $0.union($1.boundingRect) }
                let slack = max(size.width, size.height) * 0.01
                XCTAssertTrue(frame.insetBy(dx: -slack, dy: -slack).contains(drawn),
                              "\(kind) at \(size) is drawn at \(drawn), outside \(frame)")
                // And it uses the frame: the tighter side is filled to
                // within a tenth, or the horn is a speck in the corner.
                let box = BrassGlyph.box(for: kind)
                let scale = min(size.width / box.width, size.height / box.height)
                XCTAssertGreaterThan(drawn.width, box.width * scale * 0.9, "\(kind) at \(size)")
                XCTAssertGreaterThan(drawn.height, box.height * scale * 0.9, "\(kind) at \(size)")
            }
        }
    }

    /// A trumpet and a mellophone are the two that could be mistaken, both
    /// being a pipe with a bell on the end. In the same frame the trumpet
    /// has to come out visibly slimmer.
    func testATrumpetIsSlimmerThanAMellophoneInTheSameFrame() {
        let frame = CGRect(x: 0, y: 0, width: 24, height: 17)
        func height(_ kind: BrassGlyph.Kind) -> CGFloat {
            BrassGlyph.parts(for: kind, in: frame).reduce(CGRect.null) { $0.union($1.boundingRect) }.height
        }
        XCTAssertLessThan(height(.trumpet), height(.mellophone) * 0.8)
    }
}
