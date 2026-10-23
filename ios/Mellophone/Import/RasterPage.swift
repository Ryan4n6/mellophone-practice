import CoreGraphics
import Foundation

/// A page image as ink and paper, at the resolution it was printed at.
///
/// Row 0 is the TOP of the page here, the way the bitmap is laid out, and
/// everything in this file stays in pixels. Conversion to PDF user space
/// (points, y up) happens once, when RasterPageReader emits geometry.
struct InkBitmap {
    let width: Int
    let height: Int
    /// 1 is ink, 0 is paper.
    var ink: [UInt8]
    /// Pixels per PDF point.
    let scale: Double
    /// The page's height in points, for flipping y on the way out.
    let pageHeight: Double

    @_optimize(speed) @inline(__always) func at(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && ink[y * width + x] != 0
    }

    /// Draws a PDF page at the native resolution of the image it carries.
    ///
    /// An ePrint page is one image, so drawing at its own pixel size reads the
    /// pixels as printed rather than resampled. A page with no image is drawn
    /// at 300 ppi, which is a staff space of about 25 pixels on a part.
    @_optimize(speed) static func render(page: CGPDFPage, threshold: UInt8 = 160) -> InkBitmap? {
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let pixelsWide = RasterPageReader.largestImageWidth(on: page) ?? Int(box.width * 300 / 72)
        let scale = Double(pixelsWide) / Double(box.width)
        let width = Int((Double(box.width) * scale).rounded())
        let height = Int((Double(box.height) * scale).rounded())
        var gray = [UInt8](repeating: 255, count: width * height)
        let drawn = gray.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .none
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            return true
        }
        guard drawn else { return nil }
        var ink = [UInt8](repeating: 0, count: width * height)
        ink.withUnsafeMutableBufferPointer { out in
            gray.withUnsafeBufferPointer { g in
                var i = 0
                while i < width * height { if g[i] < threshold { out[i] = 1 }; i += 1 }
            }
        }
        return InkBitmap(width: width, height: height, ink: ink, scale: scale, pageHeight: Double(box.height))
    }
}

/// One staff found in the pixels: five line centres, top line first, and the
/// span the lines run.
struct PixelStaff {
    /// Line centre rows, TOP line first (pixel rows grow downward).
    let lineRows: [Double]
    let thickness: Double
    let x0: Int
    let x1: Int
    var space: Double { (lineRows[4] - lineRows[0]) / 4 }
    var top: Double { lineRows[0] }
    var bottom: Double { lineRows[4] }
}

enum PixelStaffFinder {

    /// A staff line runs at least this share of the page width. A part's
    /// shortest line is the indented first one or a short last one, and both
    /// clear a fifth of the page; nothing else on a part does.
    static let minimumLineShare = 0.2

    /// Every staff on the page, top first.
    ///
    /// A row belongs to a line when one unbroken run of ink in it is long. Rows
    /// next to each other are one line drawn thick, and five lines evenly
    /// spaced are a staff, the same test StaffFitter makes on vector rules.
    @_optimize(speed) static func staves(in bitmap: InkBitmap) -> [PixelStaff] {
        let w = bitmap.width
        let minimumRun = Int(Double(w) * minimumLineShare)
        // For each row, the longest run and where it starts and ends.
        var longRows: [(row: Int, x0: Int, x1: Int)] = []
        bitmap.ink.withUnsafeBufferPointer { ink in
            for y in 0..<bitmap.height {
                var best = (length: 0, x0: 0, x1: 0)
                var x = 0
                let base = y * w
                while x < w {
                    if ink[base + x] != 0 {
                        let start = x
                        while x < w, ink[base + x] != 0 { x += 1 }
                        if x - start > best.length { best = (x - start, start, x - 1) }
                    } else {
                        x += 1
                    }
                }
                if best.length >= minimumRun { longRows.append((y, best.x0, best.x1)) }
            }
        }
        // Adjacent rows are one line.
        var lines: [(center: Double, thickness: Double, x0: Int, x1: Int)] = []
        var i = 0
        while i < longRows.count {
            var j = i
            while j + 1 < longRows.count, longRows[j + 1].row == longRows[j].row + 1 { j += 1 }
            let group = longRows[i...j]
            let center = Double(group.first!.row + group.last!.row) / 2
            lines.append((center, Double(group.count), group.map(\.x0).min()!, group.map(\.x1).max()!))
            i = j + 1
        }
        var staves: [PixelStaff] = []
        var k = 0
        while k + 4 < lines.count {
            let window = Array(lines[k..<(k + 5)])
            let gaps = zip(window, window.dropFirst()).map { $1.center - $0.center }
            let mean = gaps.reduce(0, +) / 4
            if mean > 4, gaps.allSatisfy({ abs($0 - mean) <= max(1.5, mean * 0.06) }) {
                staves.append(PixelStaff(lineRows: window.map(\.center),
                                         thickness: window.map(\.thickness).reduce(0, +) / 5,
                                         x0: window.map(\.x0).min()!, x1: window.map(\.x1).max()!))
                k += 5
            } else {
                k += 1
            }
        }
        return staves
    }

    /// Takes the staff lines out of the ink, leaving whatever crosses them.
    ///
    /// A pixel on a line is the line's alone when the column above and below
    /// the line's own rows is paper. Anything that crosses (a stem, a notehead,
    /// a sharp) keeps its pixels, which is the classic trade: a symbol keeps a
    /// line's width of ink where it crosses, and a hollow notehead sitting on a
    /// line keeps its ring.
    @_optimize(speed) static func removingLines(_ staves: [PixelStaff], from bitmap: InkBitmap) -> InkBitmap {
        var out = bitmap
        let w = bitmap.width
        for staff in staves {
            // The band a line's own pixels sit in, with one row either side for
            // the antialiased edge the threshold kept.
            let half = Int((staff.thickness / 2).rounded(.up))
            for row in staff.lineRows {
                let r0 = Int(row.rounded()) - half, r1 = Int(row.rounded()) + half
                for x in staff.x0...staff.x1 {
                    // Ink just past the band on either side belongs to a symbol
                    // crossing or touching the line, and keeps the column.
                    // Looked for two pixels either side too: where a whole
                    // note's thin top or bottom lies along a line, the ink
                    // just past the band is diagonal from the pixel, not over
                    // it, and erasing there opened the ring.
                    var crossed = false
                    for dx in -2...2 where bitmap.at(x + dx, r0 - 1) || bitmap.at(x + dx, r1 + 1) { crossed = true }
                    if crossed { continue }
                    for y in max(0, r0)...min(bitmap.height - 1, r1) { out.ink[y * w + x] = 0 }
                }
            }
        }
        return out
    }
}

extension PixelStaffFinder {

    /// Ledger lines out, the same way as staff lines: a short rule a whole
    /// space beyond the staff, or beyond the ledger before it. Left in, a
    /// ledger line through a half note runs on along its middle row and the
    /// head reads as twice as wide as it is.
    ///
    /// Only a rule with a note on it is a ledger line. The crossbar of a bold
    /// 4 in a multi-bar rest's count is a short thin rule a space over the
    /// staff too, and taking it out read every 4 on PEAK as a 1. A note on a
    /// ledger is a filled head's core on the rule, or the two halves of a
    /// hollow head's hole either side of it.
    @_optimize(speed) static func removingLedgers(_ staves: [PixelStaff], from bitmap: InkBitmap,
                                cores: [(x: Double, y: Double)], holes: [PixelHole]) -> InkBitmap {
        var out = bitmap
        let w = bitmap.width
        for staff in staves {
            let half = Int((staff.thickness / 2).rounded(.up))
            for direction in [-1.0, 1.0] {
                for k in 1...6 {
                    let row = (direction < 0 ? staff.top : staff.bottom) + direction * Double(k) * staff.space
                    let r0 = Int(row.rounded()) - half - 1, r1 = Int(row.rounded()) + half + 1
                    guard r0 > 1, r1 < bitmap.height - 2 else { continue }
                    for y in r0...r1 {
                        var x = staff.x0
                        while x <= staff.x1 {
                            guard bitmap.at(x, y) else { x += 1; continue }
                            let start = x
                            while x <= staff.x1, bitmap.at(x, y) { x += 1 }
                            let length = Double(x - start) / staff.space
                            guard length >= 1.0, length <= 3.5 else { continue }
                            let span = Double(start)...Double(x - 1)
                            let noted = cores.contains { span.contains($0.x) && abs($0.y - row) <= 0.8 * staff.space }
                                || holes.contains { hole in
                                    // The hollow head's hole, rejoined across
                                    // the rule by PixelHoles.find, straddles it.
                                    span.contains(hole.cx) && Double(hole.y0) < row && Double(hole.y1) > row
                                        && Double(hole.y1 - hole.y0 + 1) <= 1.1 * staff.space
                                        && Double(hole.x1 - hole.x0 + 1) >= 0.5 * staff.space
                                }
                            guard noted else { continue }
                            for column in start..<x {
                                // The rule's own rows in this column.
                                var top = y, bottom = y
                                while top > r0 - 2, bitmap.at(column, top - 1) { top -= 1 }
                                while bottom < r1 + 2, bitmap.at(column, bottom + 1) { bottom += 1 }
                                guard Double(bottom - top + 1) <= staff.thickness + 2 else { continue }
                                var crossed = false
                                for dx in -2...2 where bitmap.at(column + dx, top - 1) || bitmap.at(column + dx, bottom + 1) { crossed = true }
                                if crossed { continue }
                                for row in top...bottom { out.ink[row * w + column] = 0 }
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}

/// A connected piece of ink.
struct InkBlob {
    var x0: Int, y0: Int, x1: Int, y1: Int
    var count: Int
    var width: Int { x1 - x0 + 1 }
    var height: Int { y1 - y0 + 1 }
}

enum InkComponents {

    /// 8-connected components, with a label image so a blob's own pixels can
    /// be looked at again. Labels start at 1; 0 is paper.
    @_optimize(speed) static func label(_ bitmap: InkBitmap) -> (labels: [Int32], blobs: [InkBlob]) {
        label(bitmap, diagonal: true)
    }

    @_optimize(speed) static func label4(_ bitmap: InkBitmap) -> (labels: [Int32], blobs: [InkBlob]) {
        label(bitmap, diagonal: false)
    }

    /// Run by run rather than pixel by pixel: a page is 19 million pixels
    /// and a few hundred thousand runs, and in a debug build, which the tests
    /// run, the pixel loop took a minute a page.
    @_optimize(speed) private static func label(_ bitmap: InkBitmap, diagonal: Bool) -> (labels: [Int32], blobs: [InkBlob]) {
        let w = bitmap.width, h = bitmap.height
        let reach = diagonal ? 1 : 0
        var parent: [Int32] = [0]
        // Every run: its row, first and last column, provisional label.
        var runRow: [Int32] = [], runX0: [Int32] = [], runX1: [Int32] = [], runLabel: [Int32] = []
        var rowStart = [Int](repeating: 0, count: h + 1)
        func find(_ a: Int32) -> Int32 {
            var a = a
            while parent[Int(a)] != a {
                let up = parent[Int(parent[Int(a)])]
                parent[Int(a)] = up
                a = up
            }
            return a
        }
        bitmap.ink.withUnsafeBufferPointer { ink in
            var previous = 0..<0
            for y in 0..<h {
                rowStart[y] = runRow.count
                let base = y * w
                var x = 0
                var cursor = previous.lowerBound
                while x < w {
                    if ink[base + x] == 0 { x += 1; continue }
                    let start = x
                    while x < w && ink[base + x] != 0 { x += 1 }
                    let end = x - 1
                    var mine: Int32 = 0
                    // Runs of the row above that touch this one. The cursor
                    // only moves forward: both rows are in x order.
                    while cursor < previous.upperBound && Int(runX1[cursor]) < start - reach { cursor += 1 }
                    var k = cursor
                    while k < previous.upperBound && Int(runX0[k]) <= end + reach {
                        let other = find(runLabel[k])
                        if mine == 0 {
                            mine = other
                        } else if other != mine {
                            if other < mine { parent[Int(mine)] = other; mine = other } else { parent[Int(other)] = mine }
                        }
                        k += 1
                    }
                    if mine == 0 {
                        mine = Int32(parent.count)
                        parent.append(mine)
                    }
                    runRow.append(Int32(y)); runX0.append(Int32(start)); runX1.append(Int32(end)); runLabel.append(mine)
                }
                previous = rowStart[y]..<runRow.count
            }
        }
        rowStart[h] = runRow.count
        // Dense labels, numbered in order of first appearance.
        var dense = [Int32](repeating: 0, count: parent.count)
        var blobs: [InkBlob] = []
        var labels = [Int32](repeating: 0, count: w * h)
        labels.withUnsafeMutableBufferPointer { lab in
            for r in 0..<runRow.count {
                let root = Int(find(runLabel[r]))
                if dense[root] == 0 {
                    blobs.append(InkBlob(x0: Int.max, y0: Int.max, x1: -1, y1: -1, count: 0))
                    dense[root] = Int32(blobs.count)
                }
                let d = dense[root]
                let i = Int(d) - 1
                let y = Int(runRow[r]), x0 = Int(runX0[r]), x1 = Int(runX1[r])
                if x0 < blobs[i].x0 { blobs[i].x0 = x0 }
                if x1 > blobs[i].x1 { blobs[i].x1 = x1 }
                if y < blobs[i].y0 { blobs[i].y0 = y }
                if y > blobs[i].y1 { blobs[i].y1 = y }
                blobs[i].count += x1 - x0 + 1
                let base = y * w
                var x = x0
                while x <= x1 { lab[base + x] = d; x += 1 }
            }
        }
        return (labels, blobs)
    }
}

enum InkDistance {
    /// Chamfer 3-4 distance from every ink pixel to the nearest paper, in
    /// pixels. A notehead is the only thing on a part thick enough to keep a
    /// core a third of a space deep: a beam, a rest, a clef, a digit and a
    /// stem are all thinner than that.
    @_optimize(speed) static func transform(_ bitmap: InkBitmap) -> [Float] {
        let w = bitmap.width, h = bitmap.height
        // In whole chamfer units (3 across, 4 diagonal), on raw pointers with
        // the minimum written out: the generic min and the bounds checks cost
        // a minute a page in a debug build.
        var units = [Int32](repeating: 0, count: w * h)
        units.withUnsafeMutableBufferPointer { buffer in
            let d = buffer.baseAddress!
            bitmap.ink.withUnsafeBufferPointer { ink in
                var i = 0
                while i < w * h { if ink[i] != 0 { d[i] = 1 << 28 }; i += 1 }
            }
            // While loops, not ranges: a range's iterator is a generic call
            // per step in a debug build.
            var y = 0
            while y < h {
                let row = y * w
                var x = 0
                while x < w {
                    let i = row + x
                    var v = d[i]
                    if v != 0 {
                        let left: Int32 = x > 0 ? d[i - 1] + 3 : 3
                        if left < v { v = left }
                        if y > 0 {
                            let up = d[i - w] + 3
                            if up < v { v = up }
                            if x > 0 { let a = d[i - w - 1] + 4; if a < v { v = a } }
                            if x + 1 < w { let b = d[i - w + 1] + 4; if b < v { v = b } }
                        } else if 3 < v { v = 3 }
                        d[i] = v
                    }
                    x += 1
                }
                y += 1
            }
            y = h - 1
            while y >= 0 {
                let row = y * w
                var x = w - 1
                while x >= 0 {
                    let i = row + x
                    var v = d[i]
                    if v != 0 {
                        let right: Int32 = x + 1 < w ? d[i + 1] + 3 : 3
                        if right < v { v = right }
                        if y + 1 < h {
                            let down = d[i + w] + 3
                            if down < v { v = down }
                            if x + 1 < w { let a = d[i + w + 1] + 4; if a < v { v = a } }
                            if x > 0 { let b = d[i + w - 1] + 4; if b < v { v = b } }
                        } else if 3 < v { v = 3 }
                        d[i] = v
                    }
                    x -= 1
                }
                y -= 1
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        out.withUnsafeMutableBufferPointer { o in
            units.withUnsafeBufferPointer { u in
                var i = 0
                while i < w * h { o[i] = Float(u[i]) / 3; i += 1 }
            }
        }
        return out
    }
}
