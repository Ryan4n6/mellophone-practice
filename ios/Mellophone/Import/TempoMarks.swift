import Foundation

/// A metronome mark found on a page: a note, "=", a number (#41).
///
/// Read off the page's glyphs rather than its staves, because every one of
/// them is TEXT: ScoreBuilder drops text fonts when it assigns glyphs to a
/// staff, and that is what kept the tempo off every chart until now.
struct TempoMark {
    let x: Double
    let y: Double
    /// The number as printed: 120 in "♩ = 120", 160 in "♩ = 160+".
    let printed: Int
    /// The length of the note the number counts, in quarter notes. A dotted
    /// quarter is 1.5.
    let noteQuarters: Double

    /// Quarter notes per minute, whatever note the page counted in.
    var quartersPerMinute: Double { Double(printed) * noteQuarters }
}

enum TempoMarks {

    /// The note a mark counts in, by codepoint, for codepoints that mean a
    /// note in ANY font: the SMuFL metronome marks (LelandText draws
    /// MuseScore's), and SMuFL's individual notes, which are the same shapes
    /// at a different address.
    private static let smuflNotes: [UInt32: Double] = [
        0xECA2: 4, 0xECA3: 2, 0xECA4: 2, 0xECA5: 1, 0xECA6: 1,
        0xECA7: 0.5, 0xECA8: 0.5, 0xECA9: 0.25, 0xECAA: 0.25,
        0xE1D2: 4, 0xE1D3: 2, 0xE1D4: 2, 0xE1D5: 1, 0xE1D6: 1,
        0xE1D7: 0.5, 0xE1D8: 0.5, 0xE1D9: 0.25, 0xE1DA: 0.25,
    ]
    private static let smuflDots: Set<UInt32> = [0xECB7, 0xE1E7]

    /// Sibelius writes the note as a plain letter in its Opus Text font: PEAK's
    /// "♩ = 120" is `q` in OpusTextStd. A `q` in any other font is a letter,
    /// which is why these are keyed to the font.
    private static let opusLetters: [UInt32: Double] = [
        0x77: 4, 0x68: 2, 0x71: 1, 0x65: 0.5, 0x78: 0.25,   // w h q e x
    ]

    /// How far apart two glyphs of one mark may sit, in points. The widest gap
    /// measured is Florida's tab before the number, 6.9 from the "=" to the
    /// first digit; an unrelated word is further off than this.
    private static let glyphGap: Double = 12
    /// How far off one baseline a glyph of the same mark may sit, in points.
    /// Measured 0.0 on both charts.
    private static let baseline: Double = 1.5

    private static func isBlank(_ scalar: UInt32) -> Bool {
        scalar == 0x20 || scalar == 0x09 || scalar == 0xA0
    }

    /// The note length a glyph stands for when it opens a mark, or nil.
    private static func noteQuarters(of glyph: PlacedGlyph) -> Double? {
        if let quarters = smuflNotes[glyph.scalar] { return quarters }
        if glyph.font.contains("OpusText"), let quarters = opusLetters[glyph.scalar] { return quarters }
        return nil
    }

    /// Every mark on a page, left to right within a line.
    ///
    /// A mark is a note, an optional dot, "=", then digits, on one baseline
    /// with nothing but blanks between. Anything else after the "=" is left
    /// alone: "♩ = ♩." is a metric modulation and carries no number, and
    /// reading the digits of a bar number or a rehearsal mark as a tempo would
    /// be worse than reading nothing, because the student would trust it.
    static func find(on page: PageGeometry) -> [TempoMark] {
        var marks: [TempoMark] = []
        for note in page.glyphs {
            guard var quarters = noteQuarters(of: note) else { continue }
            let line = page.glyphs
                .filter { abs($0.y - note.y) <= baseline && $0.x > note.x }
                .sorted { $0.x < $1.x }

            var cursor = 0, previousX = note.x
            func next() -> PlacedGlyph? {
                guard cursor < line.count, line[cursor].x - previousX <= glyphGap else { return nil }
                defer { previousX = line[cursor].x; cursor += 1 }
                return line[cursor]
            }
            func skipBlanks() {
                while cursor < line.count, isBlank(line[cursor].scalar), line[cursor].x - previousX <= glyphGap {
                    previousX = line[cursor].x
                    cursor += 1
                }
            }

            // A dot after the note. MuseScore sets a tab between the two
            // (measured in the fixture, 2.0 apart). Opus Text's own "." counts
            // only in that font: elsewhere a full stop before "=" is
            // punctuation.
            skipBlanks()
            if cursor < line.count,
               smuflDots.contains(line[cursor].scalar)
                || (line[cursor].scalar == 0x2E && line[cursor].font.contains("OpusText")),
               line[cursor].x - previousX <= glyphGap {
                quarters *= 1.5
                _ = next()
            }
            skipBlanks()
            guard let equals = next(), equals.scalar == 0x3D else {
                Log.score.debug("[IMPORT] a note glyph at x \(note.x, privacy: .public) y \(note.y, privacy: .public) is not followed by \"=\", not a tempo mark")
                continue
            }
            skipBlanks()
            var digits = ""
            while cursor < line.count, (0x30...0x39).contains(line[cursor].scalar),
                  line[cursor].x - previousX <= glyphGap {
                digits.unicodeScalars.append(Unicode.Scalar(line[cursor].scalar)!)
                previousX = line[cursor].x
                cursor += 1
            }
            // 20 to 400 is every tempo a part is played at. Outside it, the
            // digits are something else and the chart keeps the student's number.
            guard let printed = Int(digits), (20...400).contains(printed) else {
                Log.score.error("[IMPORT] note = at x \(note.x, privacy: .public) y \(note.y, privacy: .public) has no tempo after it (read \"\(digits, privacy: .public)\")")
                continue
            }
            marks.append(TempoMark(x: note.x, y: note.y, printed: printed, noteQuarters: quarters))
        }
        return marks
    }
}
