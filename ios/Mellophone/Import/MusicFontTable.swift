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
/// specification, and the Petrucci half was measured rather than recalled: see
/// the note on the articulations.
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
        0xE4E3: .rest(.whole), 0xE4E4: .rest(.half),
        0xE4E5: .rest(.quarter), 0xE4E6: .rest(.eighth), 0xE4E7: .rest(.sixteenth),
        0xE080: .timeSigDigit(0), 0xE081: .timeSigDigit(1), 0xE082: .timeSigDigit(2),
        0xE083: .timeSigDigit(3), 0xE084: .timeSigDigit(4), 0xE085: .timeSigDigit(5),
        0xE086: .timeSigDigit(6), 0xE087: .timeSigDigit(7), 0xE088: .timeSigDigit(8),
        0xE089: .timeSigDigit(9),
    ]

    // MARK: - Petrucci (Sibelius's Opus, Finale's Maestro)

    private static let petrucci: [UInt32: MusicSymbol] = [
        0x0077: .noteheadWhole,      // w
        0x0152: .noteheadHalf,       // OE ligature
        0x0153: .noteheadBlack,      // oe ligature
        0x0026: .gClef,              // &
        0x003F: .fClef,              // ?
        0x0062: .flat,               // b
        0x006E: .natural,            // n
        0x0023: .sharp,              // #
        0x002E: .augmentationDot,    // .   sits to the RIGHT of a notehead

        // Measured off PEAK mello.pdf rather than recalled. Each of these rides
        // a notehead (98% to 100% of occurrences share a notehead's x) and sits
        // outside the staff, which is what an articulation does and what a rest
        // never does. An earlier draft had none of them, so they fell through to
        // .unknown, and U+02D9 in particular would have been taken for a second
        // augmentation dot and lengthened all fifty staccato notes on that part.
        0x003E: .articulation,       // >   accent,   105 occurrences
        0x002D: .articulation,       // -   tenuto,    63
        0x02D9: .articulation,       // dot above, staccato, 50
        0x005E: .articulation,       // ^   marcato,   35

        0x006A: .flag(count: 1, up: true),   // j
        0x004A: .flag(count: 1, up: false),  // J
        0x2211: .rest(.quarter),
        0x00CE: .rest(.whole), 0x00CF: .rest(.half),

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
