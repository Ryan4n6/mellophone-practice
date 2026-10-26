import Foundation

/// A 1st or 2nd ending found on a page (#46): the bracket's hook and the
/// numbers printed inside it.
struct EndingMark {
    /// The hook's x, which stands on the barline the ending opens at.
    let x: Double
    /// The bottom of the hook, which is also the numbers' baseline.
    let y: Double
    /// How tall the hook is, in points, for ScoreBuilder to hold against the
    /// staff's own size.
    let hookHeight: Double
    /// The passes it is played on: [1] for "1.", [1, 2] for "1. 2.".
    let passes: [Int]
}

/// A jump or a sign for one (#48), found on a page: a segno, a coda sign, or
/// the words of a D.S., a D.C., "To Coda" or "Fine".
struct JumpMark {
    enum Kind: Equatable {
        case segno
        case coda
        case toCoda
        case fine
        case sign(JumpSign)
    }
    let kind: Kind
    /// The first glyph's origin: the bar it stands over is the bar it is for.
    let x: Double
    let y: Double
}

enum RepeatMarks {

    /// SMuFL's segno and coda. MuseScore sets them in BravuraText over the
    /// bar they mark (measured in `jumps-ds.pdf`); the same codepoints in
    /// Leland or Bravura mean the same. Sibelius's and Finale's have not been
    /// seen on a part and are not mapped: a guessed codepoint that is really
    /// something else would send the part back to the wrong bar.
    static let segnoScalar: UInt32 = 0xE047
    static let codaScalar: UInt32 = 0xE048
    /// How far a word's letters may sit apart and still be one phrase, in
    /// points. MuseScore puts a tab between the words of "D.S. al Coda",
    /// 11.5 points from one word's start to the next.
    private static let wordGap: Double = 16

    /// What a phrase on a page says, if it is a jump. Read without spaces,
    /// stops or case, so "D.S.\tal\tCoda", "D. S. al Coda" and
    /// "Dal Segno al Coda" are one thing.
    static func jump(named text: String) -> JumpMark.Kind? {
        let key = String(text.lowercased().unicodeScalars.filter { CharacterSet.letters.contains($0) }.map(Character.init))
        switch key {
        case "tocoda": return .toCoda
        case "fine": return .fine
        case "dsalcoda", "dalsegnoalcoda": return .sign(JumpSign(back: .dalSegno, until: .coda))
        case "dsalfine", "dalsegnoalfine": return .sign(JumpSign(back: .dalSegno, until: .fine))
        case "dcalcoda", "dacapoalcoda": return .sign(JumpSign(back: .daCapo, until: .coda))
        case "dcalfine", "dacapoalfine": return .sign(JumpSign(back: .daCapo, until: .fine))
        case "ds", "dalsegno": return .sign(JumpSign(back: .dalSegno, until: .end))
        case "dc", "dacapo": return .sign(JumpSign(back: .daCapo, until: .end))
        default: return nil
        }
    }

    /// Every jump mark on a page. Which staff and bar each is for is
    /// ScoreBuilder's question.
    ///
    /// Words are text glyphs strung along one baseline. A whole line of text
    /// is read as one phrase and must BE the jump, so a title that only
    /// mentions one, or a word like "Finale", is not taken for it.
    static func jumps(on page: PageGeometry) -> [JumpMark] {
        var marks: [JumpMark] = []
        var coveredByToCoda: [(x0: Double, x1: Double, y: Double)] = []
        let text = page.glyphs.filter { MusicFontTable.forFont($0.font) == nil }
        var used = Set<Int>()
        for start in text.indices where !used.contains(start) {
            // Only from the left end of a line: the tail of a longer phrase,
            // "Fine" at the end of "Horn Fine", is not a phrase of its own.
            guard !text.contains(where: { abs($0.y - text[start].y) <= 1.5 && $0.x < text[start].x
                && text[start].x - $0.x <= wordGap }) else { continue }
            // The glyphs along its baseline to the right, until a gap wider
            // than words are set apart.
            let along = text.indices.filter { !used.contains($0) && abs(text[$0].y - text[start].y) <= 1.5
                && text[$0].x >= text[start].x }.sorted { text[$0].x < text[$1].x }
            var line: [Int] = []
            var lastX = text[start].x
            for k in along {
                guard text[k].x - lastX <= wordGap else { break }
                line.append(k)
                lastX = text[k].x
            }
            line.sort { text[$0].x < text[$1].x }
            let phrase = String(line.compactMap { Unicode.Scalar(text[$0].scalar).map(Character.init) })
            guard let kind = jump(named: phrase) else { continue }
            used.formUnion(line)
            let first = text[line[0]]
            marks.append(JumpMark(kind: kind, x: first.x, y: first.y))
            if kind == .toCoda { coveredByToCoda.append((first.x, lastX + 2 * first.size, first.y)) }
            Log.score.info("[REPEAT] \(phrase.replacingOccurrences(of: "\t", with: " "), privacy: .public) at x \(first.x, privacy: .public) y \(first.y, privacy: .public)")
        }
        for glyph in page.glyphs where glyph.scalar == segnoScalar || glyph.scalar == codaScalar {
            // A coda sign printed after "To Coda" is part of that phrase, not
            // the coda itself.
            if glyph.scalar == codaScalar, coveredByToCoda.contains(where: {
                abs($0.y - glyph.y) <= 3 && glyph.x >= $0.x0 && glyph.x <= $0.x1
            }) { continue }
            marks.append(JumpMark(kind: glyph.scalar == segnoScalar ? .segno : .coda, x: glyph.x, y: glyph.y))
        }
        return marks
    }


    /// How far off the hook's foot the numbers' baseline may sit, in points.
    /// Measured 0.00 on every ending in Florida and the fixture.
    private static let baseline: Double = 1.5
    /// How far right of the hook the numbers may run, in points. Measured: the
    /// digit 2.1 to 2.8 after it, its dot 6.3 after that.
    private static let numberReach: Double = 25

    /// Every ending on a page.
    ///
    /// MuseScore draws an ending as ONE open path, not filled: up the hook,
    /// along the top, and on a closed ending down the far hook, so three or
    /// four corners. "1." sits on the hook's foot just inside it, in a text
    /// font. Both are required: a tuplet bracket has a number too but no dot
    /// and its hooks point at the notes, and a "1." with no bracket over it is
    /// not an ending anyone engraved.
    static func endings(on page: PageGeometry) -> [EndingMark] {
        var marks: [EndingMark] = []
        for path in page.paths where !path.filled && (3...4).contains(path.vertices.count) {
            let v = path.vertices
            let foot = v[0], top = v[1], along = v[2]
            guard abs(foot.x - top.x) < 0.1, top.y > foot.y,
                  abs(along.y - top.y) < 0.1, along.x > top.x + 10 else { continue }
            let footX = Double(foot.x), footY = Double(foot.y)
            let inside = page.glyphs
                .filter { glyph in
                    let onBaseline = abs(glyph.y - footY) <= baseline
                    return onBaseline && glyph.x > footX && glyph.x < footX + numberReach
                }
                .sorted { $0.x < $1.x }
            let passes = inside.compactMap { glyph -> Int? in
                (0x31...0x39).contains(glyph.scalar) ? Int(glyph.scalar) - 0x30 : nil
            }
            guard !passes.isEmpty, inside.contains(where: { $0.scalar == 0x2E }) else { continue }
            marks.append(EndingMark(x: Double(foot.x), y: Double(foot.y),
                                    hookHeight: Double(top.y - foot.y), passes: passes))
        }
        return marks
    }
}
