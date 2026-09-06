import XCTest
@testable import Mellophone

/// The codepoints here were read out of the real charts in issue #19, not from
/// a specification. Leland is SMuFL; Opus predates SMuFL and uses the legacy
/// Petrucci layout, where the notehead glyphs land on the Latin-1 ligature
/// codepoints. The two tables disagree on every value, which is the whole
/// reason the table is a lookup and not a constant.
final class MusicFontTableTests: XCTestCase {

    func testLelandIsRecognisedAsSMuFL() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("Leland"))
        XCTAssertEqual(t.symbol(for: 0xE0A4), .noteheadBlack)
        XCTAssertEqual(t.symbol(for: 0xE0A3), .noteheadHalf)
        XCTAssertEqual(t.symbol(for: 0xE050), .gClef)
        XCTAssertEqual(t.symbol(for: 0xE260), .flat)
        XCTAssertEqual(t.symbol(for: 0xE261), .natural)
        XCTAssertEqual(t.symbol(for: 0xE262), .sharp)
    }

    func testOpusUsesLegacyPetrucciCodesForTheSameSymbols() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x0153), .noteheadBlack)   // oe ligature
        XCTAssertEqual(t.symbol(for: 0x0152), .noteheadHalf)    // OE ligature
        XCTAssertEqual(t.symbol(for: 0x0077), .noteheadWhole)   // w
        XCTAssertEqual(t.symbol(for: 0x0026), .gClef)           // &
        XCTAssertEqual(t.symbol(for: 0x0062), .flat)            // b
        XCTAssertEqual(t.symbol(for: 0x0023), .sharp)           // #
        XCTAssertEqual(t.symbol(for: 0x006E), .natural)         // n
    }

    /// Subset prefixes ("ABCDEF+Leland") and the Std/Text/Special suffixes
    /// Sibelius uses must all resolve, because that is how they arrive in a
    /// real PDF.
    func testFontNamesAreMatchedLoosely() {
        XCTAssertNotNil(MusicFontTable.forFont("ABCDEF+Leland"))
        XCTAssertNotNil(MusicFontTable.forFont("OpusSpecialStd"))
        XCTAssertNotNil(MusicFontTable.forFont("Maestro"))
        XCTAssertNil(MusicFontTable.forFont("Quicksand-SemiBold"))
        XCTAssertNil(MusicFontTable.forFont("Edwin-Roman"))
    }

    /// The text companion faces are NOT notation. LelandText and OpusTextStd
    /// carry dynamics, rehearsal marks and tempo words, and both charts in
    /// issue #19 embed one alongside the real music font. Matching them would
    /// feed their letterforms into the glyph stream as noteheads.
    func testTextCompanionFacesAreNotTreatedAsNotation() {
        XCTAssertNil(MusicFontTable.forFont("LelandText"))
        XCTAssertNil(MusicFontTable.forFont("OpusTextStd"))
        XCTAssertNotNil(MusicFontTable.forFont("OpusStd"))
        XCTAssertNotNil(MusicFontTable.forFont("OpusSpecialStd"))
    }

    /// Articulations ride a notehead exactly the way an augmentation dot does.
    /// U+02D9 is a staccato dot and U+002E is an augmentation dot, and reading
    /// the first as the second lengthens every staccato note on the page. These
    /// values were measured off PEAK mello.pdf (105 accents, 63 tenuti, 50
    /// staccati, 35 marcati), not guessed.
    func testOpusArticulationsAreNotMistakenForDots() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x003E), .articulation)   // accent
        XCTAssertEqual(t.symbol(for: 0x002D), .articulation)   // tenuto
        XCTAssertEqual(t.symbol(for: 0x005E), .articulation)   // marcato
        XCTAssertEqual(t.symbol(for: 0x02D9), .articulation)   // staccato
        XCTAssertEqual(t.symbol(for: 0x002E), .augmentationDot)
    }

    /// An unrecognised codepoint is retained rather than dropped, so a chart
    /// that defeats the reader can report which glyphs did it.
    func testUnknownScalarsAreRetained() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("Leland"))
        XCTAssertEqual(t.symbol(for: 0xE999), .unknown(0xE999))
    }

    /// Dotted values are rationals, not floats, because the measure-sum check
    /// compares them for equality. A dotted half is three quarters exactly.
    func testDottedValuesAreExact() {
        XCTAssertEqual(NoteValue.half.dotted(1), NoteValue(3, 4))
        XCTAssertEqual(NoteValue.quarter.dotted(1), NoteValue(3, 8))
        XCTAssertEqual(NoteValue.half.dotted(2), NoteValue(7, 8))
        XCTAssertEqual(NoteValue.quarter.beats(unit: 4), 1.0)
        XCTAssertEqual(NoteValue.half.dotted(1).beats(unit: 4), 3.0)
    }
}
