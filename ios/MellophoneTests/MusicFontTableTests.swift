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
        XCTAssertEqual(t.symbol(for: 0x0077), .noteheadWhole)   // w
        XCTAssertEqual(t.symbol(for: 0x0026), .gClef)           // &
        XCTAssertEqual(t.symbol(for: 0x0062), .flat)            // b
        XCTAssertEqual(t.symbol(for: 0x0023), .sharp)           // #
        XCTAssertEqual(t.symbol(for: 0x006E), .natural)         // n
    }

    /// The two that were wrong and mattered.
    ///
    /// U+0152 was read as a half notehead. It is the QUARTER REST: 24
    /// occurrences in PEAK mello.pdf, every one of them at step 4.00 with no
    /// stem, and rendering it gives the zigzag. As a notehead it put 24 phantom
    /// B4 half notes into the part.
    ///
    /// U+02D9 was read as a staccato because its Unicode name is DOT ABOVE. It
    /// is the HALF NOTEHEAD: 50 occurrences, 38 with their own stem, spread
    /// over twelve staff steps, and rendering it gives a void oval. As an
    /// articulation it made 50 real notes vanish.
    ///
    /// Both sit at or near the middle line, which is why a position histogram
    /// could not separate them and structure had to.
    func testTheTwoOpusGlyphsThatWereSwapped() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x0152), .rest(.quarter))
        XCTAssertEqual(t.symbol(for: 0x02D9), .noteheadHalf)
    }

    /// All four Opus rests sit at step 4.00, so position cannot tell them
    /// apart. Framed against its own staff, the whole rest's bar hangs below
    /// the fourth line and the half rest's sits on the middle line.
    func testOpusRestsCoverWholeThroughEighth() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x2211), .rest(.whole))
        XCTAssertEqual(t.symbol(for: 0x00D3), .rest(.half))
        XCTAssertEqual(t.symbol(for: 0x0152), .rest(.quarter))
        XCTAssertEqual(t.symbol(for: 0x2030), .rest(.eighth))
    }

    /// U+00CE and U+00CF were mapped to whole and half rest on no evidence,
    /// appear in neither chart, and contradict the two rests that were actually
    /// measured. A mapping nobody has seen fire injects a wrong duration
    /// silently; an unknown says so.
    func testUnverifiedRestCodepointsWereRemovedRatherThanLeftGuessing() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x00CE), .unknown(0x00CE))
        XCTAssertEqual(t.symbol(for: 0x00CF), .unknown(0x00CF))
    }

    /// A sixteenth needs two flags, and Opus has a separate codepoint for it.
    func testOpusFlagsCarryTheirCount() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x006A), .flag(count: 1, up: true))
        XCTAssertEqual(t.symbol(for: 0x004A), .flag(count: 1, up: false))
        XCTAssertEqual(t.symbol(for: 0x0052), .flag(count: 2, up: false))
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

    /// Articulations ride a notehead the way an augmentation dot does, so the
    /// two are told apart by WHERE they ride. Measured across PEAK mello.pdf:
    /// the augmentation dot sits 4.13 half-spaces to the RIGHT of its notehead
    /// and one step up, which is where a dot goes for a note on a line. U+002E
    /// never moves right at all, 0.88 half-spaces on all 64 occurrences, which
    /// is just the notehead's own half-width, and sits a space above or below.
    /// That is a staccato. This assertion is the reverse of the one that
    /// shipped first, which lengthened 64 notes by half and lost 8 real dots.
    func testOpusArticulationsAreNotMistakenForDots() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x003E), .articulation)   // accent
        XCTAssertEqual(t.symbol(for: 0x002D), .articulation)   // tenuto
        XCTAssertEqual(t.symbol(for: 0x005E), .articulation)   // marcato
        XCTAssertEqual(t.symbol(for: 0x002E), .articulation)   // staccato
        XCTAssertEqual(t.symbol(for: 0x2122), .augmentationDot)
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
