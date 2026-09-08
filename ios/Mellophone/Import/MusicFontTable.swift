import Foundation

/// Maps one engraver's codepoints to musical meaning.
///
/// There are two conventions in the wild and they share no values. SMuFL puts
/// everything in the U+E000 private use area and is what MuseScore's Leland and
/// Bravura use. Everything older inherits Adobe Sonata's layout by way of
/// Petrucci, which parks noteheads on Latin-1 ligature codepoints and clefs on
/// ASCII punctuation; Sibelius's Opus and Finale's Maestro are both that.
///
/// Adding an engraver is adding a table here. It is never a new code path.
///
/// Every value below was read out of a real PDF (issue #19), not from a
/// specification. The Petrucci half was measured TWICE: the first pass read
/// positions only and got five values wrong, including a rest read as a
/// notehead. See the note above that table for what it takes to be sure.
struct MusicFontTable {
    private let map: [UInt32: MusicSymbol]

    func symbol(for scalar: UInt32) -> MusicSymbol {
        map[scalar] ?? .unknown(scalar)
    }

    /// Matched by substring because real PDFs carry subset prefixes
    /// ("ABCDEF+Leland") and family suffixes ("OpusSpecialStd"). Text companion
    /// faces are excluded: LelandText and OpusTextStd carry dynamics and
    /// rehearsal marks, not notation, and letting them match would put their
    /// letterforms into the glyph stream as noteheads.
    static func forFont(_ baseFont: String) -> MusicFontTable? {
        let name = baseFont.contains("+")
            ? String(baseFont.split(separator: "+").last!)
            : baseFont
        guard !name.contains("Text") else { return nil }
        if name.contains("Leland") || name.contains("Bravura") || name.contains("MScore") {
            return MusicFontTable(map: smufl)
        }
        if name.contains("Opus") || name.contains("Maestro")
            || name.contains("Petrucci") || name.contains("Sonata") {
            return MusicFontTable(map: petrucci)
        }
        return nil
    }

    // MARK: - SMuFL (MuseScore's Leland, Bravura)

    private static let smufl: [UInt32: MusicSymbol] = [
        0xE0A2: .noteheadWhole, 0xE0A3: .noteheadHalf, 0xE0A4: .noteheadBlack,
        0xE050: .gClef, 0xE062: .fClef,
        0xE260: .flat, 0xE261: .natural, 0xE262: .sharp,
        0xE1E7: .augmentationDot,
        0xE240: .flag(count: 1, up: true), 0xE241: .flag(count: 1, up: false),
        0xE242: .flag(count: 2, up: true), 0xE243: .flag(count: 2, up: false),
        // Not durations, but mapped so unreadableSymbols keeps meaning "this
        // defeated the reader". Both appear in the MuseScore chart in #19.
        0xE044: .articulation,       // repeatDot, at steps 3 and 5 of a repeat
        0xE4A1: .articulation,       // articAccentBelow

        0xE4E3: .rest(.whole), 0xE4E4: .rest(.half),
        0xE4E5: .rest(.quarter), 0xE4E6: .rest(.eighth), 0xE4E7: .rest(.sixteenth),
        0xE080: .timeSigDigit(0), 0xE081: .timeSigDigit(1), 0xE082: .timeSigDigit(2),
        0xE083: .timeSigDigit(3), 0xE084: .timeSigDigit(4), 0xE085: .timeSigDigit(5),
        0xE086: .timeSigDigit(6), 0xE087: .timeSigDigit(7), 0xE088: .timeSigDigit(8),
        0xE089: .timeSigDigit(9),
    ]

    // MARK: - Petrucci (Sibelius's Opus, Finale's Maestro)

    /// **Five of these were wrong when this table first shipped**, and the two
    /// that mattered were a rest read as a notehead and a notehead read as an
    /// ornament. They were found by classifying every Opus codepoint in
    /// PEAK mello.pdf on STRUCTURE (does it carry its own stem, which staff
    /// steps does it occupy, how far is it from the nearest notehead) and then
    /// rendering the survivors framed identically to their own staff. Position
    /// histograms alone are not enough: a rest and a notehead can both sit on
    /// the middle line, and a whole rest and a half rest differ only in whether
    /// their bar hangs below a line or sits on one.
    private static let petrucci: [UInt32: MusicSymbol] = [
        0x0077: .noteheadWhole,      // w. 37 occurrences, never stemmed
        0x0153: .noteheadBlack,      // oe ligature. 239
        // NOT an articulation, whatever its Unicode name suggests. 50
        // occurrences, 38 carrying their own stem and spread over twelve staff
        // steps, which is a melody and not an ornament. Rendered: a void oval.
        // Mapping it to .articulation made all fifty of these notes invisible.
        0x02D9: .noteheadHalf,       // dot above

        0x0026: .gClef,              // &
        0x003F: .fClef,              // ?   not present in any chart read so far
        0x0062: .flat,               // b
        0x006E: .natural,            // n
        0x0023: .sharp,              // #

        // The augmentation dot moves RIGHT of its notehead and follows its
        // pitch: measured 4.13 half-spaces across and one up, which is where a
        // dot goes for a note sitting on a line. U+002E never moves right at
        // all (0.88 half-spaces, the notehead's own half-width) and sits a
        // space above or below, which is a staccato. Having these two the wrong
        // way round lengthened 64 notes by half and lost 8 real dots.
        0x2122: .augmentationDot,    // 8 occurrences, in OpusSpecialStd
        0x002E: .articulation,       // .   staccato, 64

        0x003E: .articulation,       // >   accent,  105
        0x002D: .articulation,       // -   tenuto,   63
        0x005E: .articulation,       // ^   marcato,  35

        0x006A: .flag(count: 1, up: true),    // j
        0x004A: .flag(count: 1, up: false),   // J
        0x0052: .flag(count: 2, up: false),   // R. Rendered: two hooks

        // All four rests sit at step 4.00 exactly, so nothing about their
        // POSITION tells them apart. What does: framed against its own staff,
        // the whole rest's bar hangs below the fourth line and the half rest's
        // bar sits on the middle line. U+00CE and U+00CF were once mapped to
        // whole and half on no evidence, appear in neither chart, and
        // contradict these; an unverified mapping that injects a wrong duration
        // is worse than an unknown the reader can report, so they are gone.
        0x2211: .rest(.whole),       // 9
        0x00D3: .rest(.half),        // 17
        0x0152: .rest(.quarter),     // OE ligature. 24, never stemmed
        0x2030: .rest(.eighth),      // 32

        // NOT identifiable as a time signature by codepoint alone. In
        // PEAK mello.pdf these same glyphs appear 35 times as measure numbers
        // and multi-measure-rest counts, below the staff on a notehead's x,
        // against 8 real time signature digits. ScoreBuilder qualifies them by
        // position; this table only says "it is a digit".
        0x0030: .timeSigDigit(0), 0x0031: .timeSigDigit(1), 0x0032: .timeSigDigit(2),
        0x0033: .timeSigDigit(3), 0x0034: .timeSigDigit(4), 0x0035: .timeSigDigit(5),
        0x0036: .timeSigDigit(6), 0x0037: .timeSigDigit(7), 0x0038: .timeSigDigit(8),
        0x0039: .timeSigDigit(9),
    ]
}
