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

enum RepeatMarks {

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
