import CoreGraphics
import Foundation

/// Reads one printed digit from its pixels (#49).
///
/// A time signature, a multi-bar rest's count, a tuplet's number and a tempo
/// mark's are the only digits a part needs read. Each is matched against the
/// same digit in the open fonts `ios/scripts/make-digit-templates.swift`
/// bakes into `DigitTemplates`, all squashed to one small grid, nearest wins.
/// Vision's text reader was tried first and returned nothing for a lone "4",
/// "13" or "8" on the ePrint in #49, and took 8 seconds a crop.
enum DigitReader {

    static let columns = 10
    static let rows = 14

    struct Template {
        let digit: Int
        let cells: [Float]
        /// Width over height of the digit's ink.
        let aspect: Double
    }

    static let templates: [Template] = DigitTemplates.all.map { entry in
        Template(digit: entry.digit, cells: entry.cells.map { Float($0) / 255 }, aspect: entry.aspect)
    }

    @_optimize(speed) private static func inkBox(_ bitmap: InkBitmap, x0: Int, y0: Int, x1: Int, y1: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        var box: (x0: Int, y0: Int, x1: Int, y1: Int)?
        for y in y0...y1 { for x in x0...x1 where bitmap.at(x, y) {
            box = box.map { (min($0.x0, x), min($0.y0, y), max($0.x1, x), max($0.y1, y)) } ?? (x, y, x, y)
        } }
        return box
    }

    /// The share of ink in each cell of the grid laid over `box`.
    @_optimize(speed) private static func cells(_ bitmap: InkBitmap, box: (x0: Int, y0: Int, x1: Int, y1: Int),
                              mask: ((Int, Int) -> Bool)?) -> [Float] {
        let w = Double(box.x1 - box.x0 + 1), h = Double(box.y1 - box.y0 + 1)
        var out = [Float](repeating: 0, count: columns * rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let xa = box.x0 + Int(Double(c) * w / Double(columns)), xb = box.x0 + max(Int(Double(c + 1) * w / Double(columns)) - 1, Int(Double(c) * w / Double(columns)))
                let ya = box.y0 + Int(Double(r) * h / Double(rows)), yb = box.y0 + max(Int(Double(r + 1) * h / Double(rows)) - 1, Int(Double(r) * h / Double(rows)))
                var inkCount = 0, total = 0
                for y in ya...yb { for x in xa...xb {
                    total += 1
                    if bitmap.at(x, y), mask?(x, y) ?? true { inkCount += 1 }
                } }
                out[r * columns + c] = Float(inkCount) / Float(max(total, 1))
            }
        }
        return out
    }

    /// The digit a blob most looks like, and how far it was from it (0 is a
    /// perfect match). `mask` says which pixels in the box are the blob's own.
    /// `margin` is how much nearer the best digit is than the next best:
    /// small, and the reading is a guess.
    @_optimize(speed) static func read(_ bitmap: InkBitmap, box: (x0: Int, y0: Int, x1: Int, y1: Int),
                     mask: ((Int, Int) -> Bool)? = nil) -> (digit: Int, distance: Double, margin: Double)? {
        let grid = cells(bitmap, box: box, mask: mask)
        let aspect = Double(box.x1 - box.x0 + 1) / Double(box.y1 - box.y0 + 1)
        var nearest: [Int: Double] = [:]
        for t in templates {
            var d: Double = 0
            for i in 0..<grid.count { let e = Double(grid[i] - t.cells[i]); d += e * e }
            d = d / Double(grid.count) + 0.5 * pow(aspect - t.aspect, 2)
            nearest[t.digit] = min(nearest[t.digit] ?? .greatestFiniteMagnitude, d)
        }
        let ranked = nearest.sorted { $0.value < $1.value }
        guard var first = ranked.first else { return nil }
        let second = ranked.count > 1 ? ranked[1] : first
        // A 3 and a 5 in a rounded sans face differ only in whether the top
        // left is closed, and match each other's templates as well as their
        // own (PEAK's "= 132", 0.128 both ways). Ask that question directly:
        // ink down the left side between the top bar and the middle is a 5.
        if Set([first.key, second.key]) == [3, 5], second.value - first.value < 0.02 {
            let leftColumns = 0..<(columns / 4)
            let upperRows = (rows / 5)..<(rows * 2 / 5)
            let ink = upperRows.flatMap { r in leftColumns.map { grid[r * columns + $0] } }.reduce(0, +)
            let closed = ink / Float(upperRows.count * leftColumns.count) > 0.35
            first = (key: closed ? 5 : 3, value: first.value)
            return (first.key, first.value, 0.02)
        }
        return (first.key, first.value, second.value - first.value)
    }
}
