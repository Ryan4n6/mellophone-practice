import CoreGraphics
import Foundation

/// A thin upright stroke: a stem, a barline, an end cap, the upright of an
/// accidental or of a clef. Columns `x0...x1`, rows `y0...y1`, in pixels.
struct PixelStroke {
    var x0: Int, x1: Int, y0: Int, y1: Int
    var x: Double { Double(x0 + x1) / 2 }
    var width: Int { x1 - x0 + 1 }
    var length: Int { y1 - y0 + 1 }
}

/// A notehead found in the pixels.
struct PixelHead {
    enum Kind { case black, half, whole }
    let kind: Kind
    let x0: Int, x1: Int, y0: Int, y1: Int
    let centreY: Double
    var stem: Int?          // index into the strokes
    var stemUp = false
}

enum PixelStrokes {

    /// Every thin upright stroke at least `minimum` pixels long.
    ///
    /// Found column by column: a run of ink in one column that long, and the
    /// runs in the columns beside it that overlap it, are one stroke. A
    /// notehead is never as tall as this, so its columns stay out, and its
    /// width is never as thin, which `maximumWidth` holds.
    @_optimize(speed) static func find(in bitmap: InkBitmap, minimum: Int, maximumWidth: Int) -> [PixelStroke] {
        let w = bitmap.width, h = bitmap.height
        // Long runs per column.
        var runs: [[(y0: Int, y1: Int)]] = Array(repeating: [], count: w)
        bitmap.ink.withUnsafeBufferPointer { ink in
            for x in 0..<w {
                var y = 0
                while y < h {
                    if ink[y * w + x] != 0 {
                        let start = y
                        while y < h, ink[y * w + x] != 0 { y += 1 }
                        if y - start >= minimum { runs[x].append((start, y - 1)) }
                    } else {
                        y += 1
                    }
                }
            }
        }
        // Chain overlapping runs across neighbouring columns.
        var strokes: [PixelStroke] = []
        var open: [(stroke: Int, y0: Int, y1: Int)] = []
        for x in 0..<w {
            var next: [(stroke: Int, y0: Int, y1: Int)] = []
            for run in runs[x] {
                // The longest overlap with a stroke still open in the column before.
                let match = open.filter { min($0.y1, run.y1) - max($0.y0, run.y0) > minimum / 2 }
                    .max { min($0.y1, run.y1) - max($0.y0, run.y0) < min($1.y1, run.y1) - max($1.y0, run.y0) }
                if let match {
                    strokes[match.stroke].x1 = x
                    strokes[match.stroke].y0 = min(strokes[match.stroke].y0, run.y0)
                    strokes[match.stroke].y1 = max(strokes[match.stroke].y1, run.y1)
                    next.append((match.stroke, run.y0, run.y1))
                } else {
                    strokes.append(PixelStroke(x0: x, x1: x, y0: run.y0, y1: run.y1))
                    next.append((strokes.count - 1, run.y0, run.y1))
                }
            }
            open = next
        }
        return strokes.filter { $0.width <= maximumWidth }
    }

    /// The ink of these strokes taken out, but only where the stroke is the
    /// whole of the ink across: where a horizontal run through the pixel is no
    /// wider than the stroke. A notehead the stem touches keeps its edge.
    @_optimize(speed) static func removing(_ strokes: [PixelStroke], from bitmap: InkBitmap, slack: Int) -> InkBitmap {
        var out = bitmap
        let w = bitmap.width
        for stroke in strokes {
            for y in stroke.y0...stroke.y1 {
                var left = stroke.x0, right = stroke.x1
                while left > 0, bitmap.at(left - 1, y) { left -= 1 }
                while right < w - 1, bitmap.at(right + 1, y) { right += 1 }
                guard right - left + 1 <= stroke.width + slack else { continue }
                for x in stroke.x0...stroke.x1 { out.ink[y * w + x] = 0 }
            }
        }
        return out
    }
}

enum PixelHeads {

    /// Enclosed paper inside a blob: paper in its box that cannot reach the
    /// box's edge without crossing ink. A half note and a whole note have one,
    /// a black notehead none.
    @_optimize(speed) static func enclosedPaper(in blob: InkBlob, label: Int32, labels: [Int32], width: Int) -> Int {
        let bw = blob.width + 2, bh = blob.height + 2
        var seen = [Bool](repeating: false, count: bw * bh)
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let px = blob.x0 + x - 1, py = blob.y0 + y - 1
            guard x >= 1, y >= 1, x <= blob.width, y <= blob.height else { return false }
            return labels[py * width + px] == label
        }
        var stack = [(0, 0)]
        seen[0] = true
        var reached = 0
        while let (x, y) = stack.popLast() {
            reached += 1
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < bw, ny < bh, !seen[ny * bw + nx], !isInk(nx, ny) else { continue }
                seen[ny * bw + nx] = true
                stack.append((nx, ny))
            }
        }
        return bw * bh - reached - blob.count
    }
}

/// A hole: paper wholly enclosed by ink.
struct PixelHole {
    let x0: Int, y0: Int, x1: Int, y1: Int
    let area: Int
    /// How much of the hole's width its top row and bottom row take. The
    /// inside of a notehead is an oval and comes to a point at both; a pocket
    /// of paper closed off by two staff lines and the symbols either side of
    /// it is flat along both.
    var topShare: Double = 0
    var bottomShare: Double = 0
    /// The hole's own pixels, row by row: its first and last column in each.
    /// A tilted oval's box is no guide to where its inside is.
    var spans: [(y: Int, x0: Int, x1: Int)] = []
    var cx: Double { Double(x0 + x1) / 2 }
    var cy: Double { Double(y0 + y1) / 2 }
}

enum PixelHoles {

    /// Every enclosed piece of paper up to `maximumArea` pixels, by labelling
    /// the paper the way ink is labelled and keeping what does not reach the
    /// edge of the page.
    ///
    /// Found on the page WITH its staff lines. Taking the lines out first
    /// opens a hollow head that sits in a space, because its ring runs along
    /// the line above and the line below for a few pixels and goes with them:
    /// 24 of PEAK's 50 half notes lost their hole that way. Left in, the lines
    /// close the ring. A head ON a line has its hole cut in two by the line,
    /// and `staves` is what puts the halves back together.
    @_optimize(speed) static func find(in bitmap: InkBitmap, staves: [PixelStaff], maximumArea: Int) -> [PixelHole] {
        var paper = bitmap
        paper.ink.withUnsafeMutableBufferPointer { ink in
            var i = 0
            while i < ink.count { ink[i] = ink[i] == 0 ? 1 : 0; i += 1 }
        }
        // Paper is 4-connected where ink is 8-connected, or a diagonal gap in
        // a ring would let the hole out.
        let (labels, blobs) = InkComponents.label4(paper)
        var holes = blobs.enumerated().compactMap { index, b -> PixelHole? in
            guard b.x0 > 0, b.y0 > 0, b.x1 < bitmap.width - 1, b.y1 < bitmap.height - 1,
                  b.count <= maximumArea else { return nil }
            let label = Int32(index + 1)
            func run(_ y: Int) -> Double {
                Double((b.x0...b.x1).filter { labels[y * bitmap.width + $0] == label }.count) / Double(b.width)
            }
            var spans: [(y: Int, x0: Int, x1: Int)] = []
            for y in b.y0...b.y1 {
                let xs = (b.x0...b.x1).filter { labels[y * bitmap.width + $0] == label }
                if let first = xs.first, let last = xs.last { spans.append((y, first, last)) }
            }
            return PixelHole(x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1, area: b.count,
                             topShare: run(b.y0), bottomShare: run(b.y1), spans: spans)
        }
        // Rejoin the halves of a hollow head's hole that a line runs
        // through, a staff line or a ledger line: two small pieces one over
        // the other with only the line's thickness between them, centred on
        // one x (an oval is tilted, so the halves sit up to a third of a
        // space apart) and as wide as each other. Kept that strict because a looser
        // merge joined a head's hole to the pocket of paper beside it.
        let space = staves.map(\.space).reduce(0, +) / Double(max(staves.count, 1))
        let thickness = Int((staves.map(\.thickness).max() ?? 3).rounded(.up)) + 2
        holes.sort { $0.y0 < $1.y0 }
        var merged: [PixelHole] = []
        var used = Set<Int>()
        for i in holes.indices where !used.contains(i) {
            var hole = holes[i]
            if Double(hole.y1 - hole.y0 + 1) <= 0.55 * space,
               let j = holes.indices.first(where: { j in
                   let other = holes[j]
                   let wa = Double(hole.x1 - hole.x0 + 1), wb = Double(other.x1 - other.x0 + 1)
                   return !used.contains(j) && j != i && other.y0 > hole.y1 && other.y0 - hole.y1 <= thickness + 1
                       && Double(other.y1 - other.y0 + 1) <= 0.55 * space
                       && abs(other.cx - hole.cx) <= 0.35 * space && min(wa, wb) / max(wa, wb) >= 0.6
               }) {
                let other = holes[j]
                used.insert(j)
                // The rows the line covered, carried across from the rows
                // either side of it.
                let above = hole.spans.last!, below = other.spans.first!
                let gap = ((hole.y1 + 1)..<other.y0).map { (y: $0, x0: min(above.x0, below.x0), x1: max(above.x1, below.x1)) }
                hole = PixelHole(x0: min(hole.x0, other.x0), y0: hole.y0, x1: max(hole.x1, other.x1),
                                 y1: other.y1, area: hole.area + other.area + (other.y0 - hole.y1 - 1) * (hole.x1 - hole.x0),
                                 topShare: hole.topShare, bottomShare: other.bottomShare,
                                 spans: hole.spans + gap + other.spans)
            }
            merged.append(hole)
        }
        return merged
    }

    /// The ring round a hole, row by row from the hole's own edge: how far
    /// out its ink reaches on each side, and how thick it is in the middle
    /// of its rows (the median, so the row a tie or a stem leaves from does
    /// not count). On the page with its staff lines out.
    @_optimize(speed) static func ring(of hole: PixelHole, in clean: InkBitmap, limit: Int)
        -> (x0: Int, x1: Int, left: Int, right: Int) {
        var outerLeft = hole.x0, outerRight = hole.x1
        var lefts: [Int] = [], rights: [Int] = []
        for span in hole.spans {
            var l = 0, r = 0
            while l < limit, clean.at(span.x0 - 1 - l, span.y) { l += 1 }
            while r < limit, clean.at(span.x1 + 1 + r, span.y) { r += 1 }
            lefts.append(l); rights.append(r)
            outerLeft = min(outerLeft, span.x0 - l)
            outerRight = max(outerRight, span.x1 + r)
        }
        lefts.sort(); rights.sort()
        return (outerLeft, outerRight, lefts.isEmpty ? 0 : lefts[lefts.count / 2], rights.isEmpty ? 0 : rights[rights.count / 2])
    }

    /// The box of the ink connected to a pixel, searched no further than
    /// `limit` from it.
    @_optimize(speed) static func inkExtent(from start: (Int, Int), in bitmap: InkBitmap, limit: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        var box = (x0: start.0, y0: start.1, x1: start.0, y1: start.1)
        var seen = Set<Int>([start.1 * bitmap.width + start.0])
        var stack = [start]
        while let (x, y) = stack.popLast() {
            box = (min(box.x0, x), min(box.y0, y), max(box.x1, x), max(box.y1, y))
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                let nx = x + dx, ny = y + dy
                guard abs(nx - start.0) <= limit, abs(ny - start.1) <= limit, bitmap.at(nx, ny),
                      seen.insert(ny * bitmap.width + nx).inserted else { continue }
                stack.append((nx, ny))
            }
        }
        return box
    }
}
