import CoreGraphics
import Foundation

/// Reads a page image into the geometry the vector reader would have produced
/// from the same page drawn as vectors (#49).
///
/// Everything here is in staff spaces of the staff a thing belongs to, so one
/// set of thresholds serves any print size. They were measured on our own
/// charts rasterized at 450 ppi, where the vector read of the same page is the
/// answer, and on the ePrint in #49.
enum RasterRecognizer {

    /// The font name glyphs are emitted under. MusicFontTable maps it to the
    /// SMuFL table, and every glyph is placed where Leland would place it, so
    /// ScoreBuilder's measured offsets hold.
    static let fontName = "RasterSMuFL"
    static let textFontName = "RasterText"

    // MARK: - Thresholds, in staff spaces

    /// A filled notehead is the only ink on a part this deep. Measured 0.47 to
    /// 0.51 on Leland; the next deepest are a time signature digit 0.38, a
    /// clef 0.34 and a half or whole rest 0.30.
    static let headDepth = 0.42
    /// Strokes: a stem, a barline, an end cap. Shorter than this is a letter
    /// or a notehead's own column.
    static let strokeMinimum = 1.6
    static let strokeMaximumWidth = 0.4

    @_optimize(speed) static func read(_ bitmap: InkBitmap) -> PageGeometry {
        let staves = PixelStaffFinder.staves(in: bitmap)
        guard !staves.isEmpty else {
            Log.score.error("[RASTER] no staff found in a \(bitmap.width, privacy: .public) x \(bitmap.height, privacy: .public) picture")
            return .empty
        }
        let lineless = PixelStaffFinder.removingLines(staves, from: bitmap)
        let depth = InkDistance.transform(bitmap)
        var heads = blackHeads(depth: depth, bitmap: lineless, staves: staves)
        let holes = PixelHoles.find(in: bitmap, staves: staves, maximumArea: Int(2 * staves[0].space * staves[0].space))
        let clean = PixelStaffFinder.removingLedgers(staves, from: lineless,
                                                     cores: heads.map { (Double($0.x0 + $0.x1) / 2, $0.centreY) }, holes: holes)
        let strokes = PixelStrokes.find(in: clean, minimum: Int(strokeMinimum * staves[0].space),
                                        maximumWidth: Int(strokeMaximumWidth * staves[0].space))

        var glyphs: [PlacedGlyph] = []
        var paths: [PlacedPath] = []
        let point = 1 / bitmap.scale
        func pdfX(_ x: Double) -> Double { x * point }
        func pdfY(_ y: Double) -> Double { bitmap.pageHeight - y * point }

        // Staff lines, five strokes each across the staff.
        for staff in staves {
            for row in staff.lineRows {
                let y = pdfY(row)
                paths.append(PlacedPath(vertices: [CGPoint(x: pdfX(Double(staff.x0)), y: y),
                                                   CGPoint(x: pdfX(Double(staff.x1)), y: y)],
                                        filled: false,
                                        bounds: CGRect(x: pdfX(Double(staff.x0)), y: y,
                                                       width: Double(staff.x1 - staff.x0) * point, height: 0)))
            }
        }

        let stemOf = attachStems(to: &heads, strokes: strokes, staves: staves)
        // Anything as tall as a clef holds holes beside an upright, a half
        // note's shape exactly, so its holes and strokes are out.
        let (cleanLabels, cleanBlobs) = InkComponents.label(clean)
        // Narrow as well as tall, and at the head of its staff: a stem
        // joined to the hook of an ending is as tall and as narrow as a
        // clef, in the middle of Florida's first line.
        func clefLike(_ blob: InkBlob) -> Bool {
            let staff = staffOf(Double(blob.y0 + blob.y1) / 2, staves)
            return Double(blob.height) > 4.5 * staff.space && Double(blob.width) < 3.5 * staff.space
                && Double(blob.x0) <= Double(staff.x0) + 4 * staff.space
        }
        let tall = cleanBlobs.filter(clefLike)
        let inTall = Set(strokes.indices.filter { k in
            let stroke = strokes[k]
            let row = (stroke.y0 + stroke.y1) / 2
            return (stroke.x0...stroke.x1).contains { x in
                let label = cleanLabels[row * clean.width + x]
                return label > 0 && clefLike(cleanBlobs[Int(label) - 1])
            }
        })
        heads += hollowHeads(holes: holes, strokes: strokes, excluded: Set(stemOf.values).union(inTall),
                             tall: tall, clean: clean, staves: staves)
        // Last, on the stems nothing else claimed: an x is found from its
        // stem, and a stem a real head hangs on has no x at its end.
        heads += crossHeads(original: bitmap, strokes: strokes,
                            excluded: Set(heads.compactMap(\.stem)).union(inTall), staves: staves)
        for head in heads {
            let scalar: UInt32
            switch head.kind {
            case .black: scalar = 0xE0A4
            case .half: scalar = 0xE0A3
            case .whole: scalar = 0xE0A2
            case .x: scalar = 0xE0A9
            }
            glyphs.append(PlacedGlyph(scalar: scalar, x: pdfX(Double(head.x0)), y: pdfY(head.centreY),
                                      size: staffOf(head.centreY, staves).space * 4 * point, font: fontName))
        }

        // Stems, once each however many heads share one.
        let stems = Set(heads.compactMap(\.stem))
        for k in stems.sorted() {
            paths.append(upright(strokes[k], pdfX: pdfX, pdfY: pdfY))
        }
        // Barlines: an upright no head claimed that spans its staff, drawn
        // exactly from the bottom line to the top so ScoreBuilder's both ends
        // test holds.
        var barlines: [PixelStroke] = []
        for (k, stroke) in strokes.enumerated() where !stems.contains(k) && !inTall.contains(k) {
            let staff = staffOf(Double(stroke.y0 + stroke.y1) / 2, staves)
            guard abs(Double(stroke.y0) - staff.top) <= 0.35 * staff.space,
                  abs(Double(stroke.y1) - staff.bottom) <= 0.35 * staff.space else { continue }
            barlines.append(stroke)
            var line = stroke
            line.y0 = Int(staff.top.rounded()); line.y1 = Int(staff.bottom.rounded())
            paths.append(upright(line, pdfX: pdfX, pdfY: pdfY))
        }
        let filled = heads.filter { $0.kind == .black }.count
        let crosses = heads.filter { $0.kind == .x }.count
        Log.score.info("[RASTER] \(staves.count, privacy: .public) staves, space \(staves[0].space, format: .fixed(precision: 1), privacy: .public) px: \(filled, privacy: .public) filled heads, \(heads.count - filled - crosses, privacy: .public) hollow, \(crosses, privacy: .public) x heads, \(stems.count, privacy: .public) stems, \(barlines.count, privacy: .public) barlines")
        let rest = residue(original: bitmap, clean: clean, heads: heads, strokes: strokes, stems: stems, barlines: barlines,
                           staves: staves, tall: tall, depth: depth)
        for symbol in rest.glyphs {
            glyphs.append(PlacedGlyph(scalar: symbol.scalar, x: pdfX(symbol.x), y: pdfY(symbol.y),
                                      size: staffOf(symbol.y, staves).space * 4 * point, font: fontName))
        }
        for symbol in rest.text {
            glyphs.append(PlacedGlyph(scalar: symbol.scalar, x: pdfX(symbol.x), y: pdfY(symbol.y),
                                      size: staffOf(symbol.y, staves).space * 2 * point, font: textFontName))
        }
        for shape in rest.paths {
            let vertices = shape.points.map { CGPoint(x: pdfX($0.x), y: pdfY($0.y)) }
            let xs = vertices.map(\.x), ys = vertices.map(\.y)
            paths.append(PlacedPath(vertices: vertices, filled: shape.filled,
                                    bounds: CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!),
                                    hasCurves: shape.curved))
        }
        return PageGeometry(glyphs: glyphs, paths: paths)
    }

    /// An upright stroke as the two point line a PDF strokes a stem or a
    /// barline with: no width, at the stroke's middle.
    @_optimize(speed) static func upright(_ stroke: PixelStroke, pdfX: (Double) -> Double, pdfY: (Double) -> Double) -> PlacedPath {
        let x = pdfX(stroke.x), top = pdfY(Double(stroke.y0)), bottom = pdfY(Double(stroke.y1))
        return PlacedPath(vertices: [CGPoint(x: x, y: bottom), CGPoint(x: x, y: top)], filled: false,
                          bounds: CGRect(x: x, y: bottom, width: 0, height: top - bottom))
    }

    @_optimize(speed) static func staffOf(_ row: Double, _ staves: [PixelStaff]) -> PixelStaff {
        staves.min { distance(row, $0) < distance(row, $1) }!
    }

    @_optimize(speed) static func distance(_ row: Double, _ staff: PixelStaff) -> Double {
        row < staff.top ? staff.top - row : row > staff.bottom ? row - staff.bottom : 0
    }

    // MARK: - Filled noteheads

    /// Every core of ink deeper than `headDepth`, one per filled notehead.
    ///
    /// The core is found on the page as printed, staff lines and all: a head
    /// keeps its depth whatever touches it, a stem, a flag, a beam, a ledger
    /// line or a tie, which is why this does not work on separated blobs.
    /// The head's extent is measured on `bitmap`, the page with its staff
    /// lines out, or a head on a line runs along the line.
    @_optimize(speed) static func blackHeads(depth: [Float], bitmap: InkBitmap, staves: [PixelStaff]) -> [PixelHead] {
        let w = bitmap.width, h = bitmap.height
        let space = staves.map(\.space).reduce(0, +) / Double(staves.count)
        let floor = Float(headDepth * space)
        var core = InkBitmap(width: w, height: h, ink: [UInt8](repeating: 0, count: w * h),
                             scale: bitmap.scale, pageHeight: bitmap.pageHeight)
        core.ink.withUnsafeMutableBufferPointer { ink in
            depth.withUnsafeBufferPointer { d in
                var i = 0
                while i < w * h { if d[i] >= floor { ink[i] = 1 }; i += 1 }
            }
        }
        let (_, cores) = InkComponents.label(core)
        var heads: [PixelHead] = []
        var spans: [(cx: Int, cy: Double, left: Int, right: Int, top: Int, bottom: Int)] = []
        for c in cores {
            // A notehead's core is small and round; a thick slab (an H-bar) is
            // long.
            guard Double(c.width) < 1.0 * space, Double(c.height) < 0.8 * space,
                  Double(c.width) >= 0.2 * space else { continue }
            let cx = (c.x0 + c.x1) / 2, cy = (c.y0 + c.y1) / 2
            // The head's own extent along its middle row.
            var left = cx, right = cx
            while left > 0, bitmap.at(left - 1, cy), Double(cx - left) < 1.0 * space { left -= 1 }
            while right < w - 1, bitmap.at(right + 1, cy), Double(right - cx) < 1.0 * space { right += 1 }
            var top = cy, bottom = cy
            while top > 0, bitmap.at(cx, top - 1), Double(cy - top) < 0.8 * space { top -= 1 }
            while bottom < h - 1, bitmap.at(cx, bottom + 1), Double(bottom - cy) < 0.8 * space { bottom += 1 }
            // As wide as a notehead. A clef's ball is deep enough but narrow.
            guard Double(right - left + 1) >= 1.05 * space else { continue }
            spans.append((cx, Double(c.y0 + c.y1) / 2, left, right, top, bottom))
        }
        // The page's own notehead width, the middle of every head's measured
        // width. One head measured alone runs on into whatever touches it
        // along its middle row, a stem, a natural, the head beside it in a
        // chord, and a head that claims a natural's upright as its stem
        // leaves its real stem free to make a half note out of nothing.
        let widths = spans.map { $0.right - $0.left + 1 }.sorted()
        let half = widths.isEmpty ? 0 : Double(widths[widths.count / 2]) / 2
        for span in spans {
            let left = max(span.left, Int((Double(span.cx) - half).rounded()))
            let right = min(span.right, Int((Double(span.cx) + half).rounded()))
            heads.append(PixelHead(kind: .black, x0: left, x1: right, y0: span.top, y1: span.bottom,
                                   centreY: span.cy))
        }
        return heads
    }

    // MARK: - Stems

    /// The stem of each filled head: an upright stroke at its right edge
    /// going up, or at its left edge going down, that reaches the head's
    /// middle. Returns head index to stroke index.
    @_optimize(speed) static func attachStems(to heads: inout [PixelHead], strokes: [PixelStroke],
                            staves: [PixelStaff]) -> [Int: Int] {
        var stemOf: [Int: Int] = [:]
        for index in heads.indices {
            let head = heads[index]
            let space = staffOf(head.centreY, staves).space
            let best = strokes.indices.compactMap { k -> (k: Int, up: Bool, gap: Double)? in
                let stroke = strokes[k]
                let reaches = Double(stroke.y0) <= head.centreY + 0.6 * space && Double(stroke.y1) >= head.centreY - 0.6 * space
                guard reaches else { return nil }
                // Running on past the head in its direction. Not required to
                // START at the head: a chord's stem starts at its far note and
                // passes the others.
                let up = Double(stroke.y0) < head.centreY - 1.2 * space
                let down = Double(stroke.y1) > head.centreY + 1.2 * space
                // A stem that ENDS at this head beats one that only passes it:
                // a chord's other notes have their stem pass them, and a
                // natural's upright passes a head it touches.
                let ends = up ? Double(stroke.y1) <= head.centreY + 0.6 * space : Double(stroke.y0) >= head.centreY - 0.6 * space
                let penalty = ends ? 0 : space
                if up, abs(stroke.x - Double(head.x1)) <= 0.35 * space { return (k, true, abs(stroke.x - Double(head.x1)) + penalty) }
                if down, abs(stroke.x - Double(head.x0)) <= 0.35 * space { return (k, false, abs(stroke.x - Double(head.x0)) + penalty) }
                return nil
            }.min { $0.gap < $1.gap }
            if let best {
                stemOf[index] = best.k
                heads[index].stem = best.k
                heads[index].stemUp = best.up
            }
        }
        return stemOf
    }

    // MARK: - Hollow heads

    /// Half and whole notes: a hole with a notehead's ring round it.
    ///
    /// A hollow head is hard to tell from a pocket of paper closed off by two
    /// staff lines and the symbols either side, so the hole has to be ringed
    /// the way a notehead is: a wall either side, neither as thick as a
    /// notehead (a pocket beside a filled head has one that is), and a ring
    /// as wide as a head. Then a stem at its edge makes it a half note, and
    /// with none it is a whole note only if its two walls match, which a
    /// pocket between two different symbols does not. On Sibelius's half
    /// notes the ring IS the staff line for a few pixels, which is why holes
    /// are found with the lines in (`PixelHoles.find`).
    @_optimize(speed) static func hollowHeads(holes: [PixelHole], strokes: [PixelStroke], excluded: Set<Int>,
                            tall: [InkBlob], clean: InkBitmap, staves: [PixelStaff]) -> [PixelHead] {
        var found: [PixelHead] = []
        for hole in holes {
            let staff = staffOf(hole.cy, staves)
            let space = staff.space
            guard distance(hole.cy, staff) <= 5 * space else { continue }
            // Not inside a clef, and not inside a filled head's own pixels.
            guard !tall.contains(where: { hole.x0 >= $0.x0 && hole.x1 <= $0.x1 && hole.y0 >= $0.y0 && hole.y1 <= $0.y1 }) else { continue }
            let w = Double(hole.x1 - hole.x0 + 1) / space, h = Double(hole.y1 - hole.y0 + 1) / space
            let fill = Double(hole.area) / (w * h * space * space)
            // Measured: a half note's hole 0.62 to 1.18 across (a sharp's is
            // 0.32, a natural's 0.48) and 0.31 to 0.90 high.
            // And an oval, not a box: a pocket of paper between a barline,
            // two staff lines and a sharp fills 0.90 of its box and is flat
            // along its top and bottom; the inside of a head fills at most
            // 0.85 (PEAK's whole notes) and comes to a point at both. A hand
            // clap's x on a line closes off a triangle with the line for a
            // flat side, which is why either flat side is enough to refuse.
            guard w >= 0.55, w <= 1.3, h >= 0.3, h <= 0.98, fill >= 0.4, fill <= 0.87,
                  hole.topShare < 0.75, hole.bottomShare < 0.75 else { continue }
            let cy = hole.cy
            /// Whether another hollow head of a chord sits at this end of a
            /// stem: a hole like this one, level with the end.
            func chordEnd(_ row: Int) -> Bool {
                holes.contains { other in
                    other.x0 != hole.x0 && abs(other.cy - Double(row)) <= 0.8 * space && abs(other.cx - hole.cx) <= 1.5 * space
                        && Double(other.x1 - other.x0 + 1) >= 0.55 * space
                }
            }
            let ring = PixelHoles.ring(of: hole, in: clean, limit: Int(space))
            let wl = Double(ring.left) / space, wr = Double(ring.right) / space
            let x0 = ring.x0, x1 = ring.x1
            let outer = Double(x1 - x0 + 1) / space
            // Measured with the hole's own edge: rings 0.05 to 0.65 thick,
            // never as thick as the filled head a pocket of paper sits beside.
            guard wl >= 0.03, wr >= 0.03, wl <= 0.65, wr <= 0.65, outer >= 1.0, outer <= 2.3 else { continue }
            // A stem: at the right edge going up, or the left edge going
            // down, passing the head's middle and running on past it.
            let stem = strokes.indices.first { k in
                guard !excluded.contains(k) else { return false }
                let stroke = strokes[k]
                guard Double(stroke.length) / space >= 2.5,
                      Double(stroke.y0) <= cy + 0.6 * space, Double(stroke.y1) >= cy - 0.6 * space else { return false }
                // Not a barline: one beside a time signature made half notes
                // of the holes in its digits.
                let spans = abs(Double(stroke.y0) - staff.top) <= 0.3 * space && abs(Double(stroke.y1) - staff.bottom) <= 0.3 * space
                guard !spans else { return false }
                // Ending at this head, or at another head of its chord. A
                // sharp's uprights run on past its hole both ways, the way a
                // stem never does past its last note.
                let up = Double(stroke.y0) < cy - 1.2 * space && abs(stroke.x - Double(x1)) <= 0.35 * space
                    && (Double(stroke.y1) <= cy + 0.8 * space || chordEnd(stroke.y1))
                let down = Double(stroke.y1) > cy + 1.2 * space && abs(stroke.x - Double(x0)) <= 0.35 * space
                    && (Double(stroke.y0) >= cy - 0.8 * space || chordEnd(stroke.y0))
                return up || down
            }
            if let stem {
                var head = PixelHead(kind: .half, x0: x0, x1: x1, y0: hole.y0, y1: hole.y1, centreY: cy)
                head.stem = stem
                head.stemUp = Double(strokes[stem].y0) < cy - 1.2 * space
                found.append(head)
                continue
            }
            // A whole note: a ring of even thickness either side, as wide as a
            // notehead or wider.
            guard abs(wl - wr) <= 0.15, wl >= 0.15, wr >= 0.15, outer >= 1.4 else { continue }
            // Paper just outside the ring on one side at least, or the hole is
            // inside something bigger. One: a tie leaves a whole note's side.
            guard !clean.at(x0 - 2, Int(cy)) || !clean.at(x1 + 2, Int(cy)) else { continue }
            // No upright touching it at all: a whole note has no stem, and a
            // natural's middle is ringed by two uprights a space and a half
            // tall, too short to be a stem.
            let touched = strokes.contains { stroke in
                stroke.x >= Double(x0) - 0.3 * space && stroke.x <= Double(x1) + 0.3 * space
                    && Double(stroke.y0) <= cy + 0.6 * space && Double(stroke.y1) >= cy - 0.6 * space
            }
            guard !touched else { continue }
            // Alone: a digit 8 or 6 has a hole with even walls too, and is
            // taller than any notehead. Searched from the ring's own ink on
            // the middle row.
            var start = x0
            while start < x1, !clean.at(start, Int(cy)) { start += 1 }
            let extent = PixelHoles.inkExtent(from: (start, Int(cy)), in: clean, limit: Int(2 * space))
            // A whole-note chord is taller, two heads touching, but as wide
            // as a whole note, and a bold 8 is narrower than any: measured
            // 1.23 spaces across against 1.45 and up.
            let tallest = Double(extent.x1 - extent.x0 + 1) >= 1.4 * space ? 3.2 : 1.4
            guard Double(extent.y1 - extent.y0 + 1) <= tallest * space else { continue }
            found.append(PixelHead(kind: .whole, x0: x0, x1: x1, y0: hole.y0, y1: hole.y1, centreY: cy))
        }
        return found
    }

    // MARK: - Hand claps

    /// Hand claps (#53): an x on the free end of a stem.
    ///
    /// Found from the stem because an x has nothing deep or hollow to find it
    /// by: two strokes crossing, about a space square, the stem leaving a
    /// tip, the lower left going down or the upper right going up. Measured
    /// on our fixture drawn at 450 ppi (Leland: 1.4 spaces wide, arms a third
    /// of a space thick, between two lines) and on the ePrint (1.1 spaces
    /// square, arms a fifth of a space, centred ON the middle line). So the
    /// test is on the page with its lines IN, and a sample on a staff line's
    /// rows counts for nothing either way: both diagonals of the box at the
    /// tip are ink, and the four pockets between the arms are paper, which
    /// no filled head, ring, flag or letter at a stem's end is.
    @_optimize(speed) static func crossHeads(original: InkBitmap, strokes: [PixelStroke], excluded: Set<Int>,
                                             staves: [PixelStaff]) -> [PixelHead] {
        var found: [PixelHead] = []
        for (k, stroke) in strokes.enumerated() where !excluded.contains(k) {
            let staff = staffOf(Double(stroke.y0 + stroke.y1) / 2, staves)
            let space = staff.space
            // A barline spans the staff exactly, and the x would be its own
            // top or bottom line.
            guard abs(Double(stroke.y0) - staff.top) > 0.35 * space || abs(Double(stroke.y1) - staff.bottom) > 0.35 * space,
                  Double(stroke.length) >= 2 * space else { continue }
            for up in [false, true] {
                guard let head = cross(at: stroke, up: up, original: original, staff: staff) else { continue }
                var placed = head
                placed.stem = k
                found.append(placed)
                break
            }
        }
        if !found.isEmpty {
            Log.score.info("[RASTER] \(found.count, privacy: .public) x noteheads, read as hand claps")
        }
        return found
    }

    /// The x at one end of a stem, if there is one: above its top with the
    /// stem at its left (`up` false), or below its bottom with the stem at
    /// its right.
    ///
    /// Every box it could be fits one small patch round the tip, so the ink
    /// is looked up there, thickened by a pixel each way once: an arm is
    /// antialiased and a sample may land between two of its pixels. Written
    /// with while loops on raw buffers, like the rest of this file, because
    /// the debug build the tests run in made the first version of this, with
    /// ranges and closures, triple the time PEAK takes to read.
    @_optimize(speed) private static func cross(at stroke: PixelStroke, up: Bool, original: InkBitmap,
                                               staff: PixelStaff) -> PixelHead? {
        let space = staff.space
        let tipY = up ? stroke.y1 : stroke.y0
        let side = up ? stroke.x1 : stroke.x0
        let widest = 1.7 * space, tallest = 1.5 * space
        let w = original.width, h = original.height
        // The patch, in page pixels, and the thickened ink in it.
        let px0 = max(Int(Double(side) - widest) - 3, 1), px1 = min(Int(Double(side) + widest) + 3, w - 2)
        let py0 = max(Int(Double(tipY) - tallest - 0.3 * space) - 3, 1)
        let py1 = min(Int(Double(tipY) + tallest + 0.3 * space) + 3, h - 2)
        guard px1 > px0, py1 > py0 else { return nil }
        // Quick refusal, before anything is built: the arm the stem leaves
        // crosses the column a third of a space in from the stem, within half
        // a space past the tip, off the staff lines. A column and not a point
        // at 45 degrees, because Leland's x is wider than it is tall and its
        // arm passes under that point. Nearly every stem end on a page fails
        // here.
        let probeX = Int((Double(side) + (up ? -0.3 : 0.3) * space).rounded())
        var armFound = false
        original.ink.withUnsafeBufferPointer { ink in
            var rise = 0
            while !armFound, Double(rise) <= 0.5 * space {
                let y = up ? tipY + rise : tipY - rise
                rise += 1
                guard y > py0, y < py1, !staff.lineRows.contains(where: { abs(Double(y) - $0) <= staff.thickness / 2 + 1 }) else { continue }
                var x = probeX - 1
                while x <= probeX + 1 { if ink[y * w + x] != 0 { armFound = true }; x += 1 }
            }
        }
        guard armFound, probeX > px0, probeX < px1 else { return nil }
        let pw = px1 - px0 + 1, ph = py1 - py0 + 1
        var near = [Bool](repeating: false, count: pw * ph)
        original.ink.withUnsafeBufferPointer { ink in
            var y = py0
            while y <= py1 {
                var x = px0
                while x <= px1 {
                    var hit = false
                    var yy = y - 1
                    while !hit, yy <= y + 1 {
                        var xx = x - 1
                        while xx <= x + 1 { if ink[yy * w + xx] != 0 { hit = true; break }; xx += 1 }
                        yy += 1
                    }
                    near[(y - py0) * pw + (x - px0)] = hit
                    x += 1
                }
                y += 1
            }
        }
        // A sample on a staff line's rows says nothing either way.
        var lineRow = [Bool](repeating: false, count: ph)
        var row = 0
        while row < ph {
            let y = Double(py0 + row)
            lineRow[row] = staff.lineRows.contains { abs(y - $0) <= staff.thickness / 2 + 1 }
            row += 1
        }
        /// 1 ink, 0 paper, -1 on a staff line or outside the patch.
        func look(_ x: Double, _ y: Double) -> Int {
            let cx = Int(x.rounded()) - px0, cy = Int(y.rounded()) - py0
            guard cx >= 0, cx < pw, cy >= 0, cy < ph, !lineRow[cy] else { return -1 }
            return near[cy * pw + cx] ? 1 : 0
        }
        /// Whether a line from a to b is ink along 85% of what can be
        /// judged of it, staff line rows left out. Stops at the fourth miss,
        /// past which it cannot be.
        func inked(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Bool {
            var hit = 0, seen = 0, missed = 0, i = 0
            while i < 24, missed < 4 {
                let t = 0.08 + 0.84 * Double(i) / 23
                let value = look(ax + (bx - ax) * t, ay + (by - ay) * t)
                if value >= 0 { seen += 1; if value == 1 { hit += 1 } else { missed += 1 } }
                i += 1
            }
            return seen >= 12 && Double(hit) >= 0.85 * Double(seen)
        }

        var best: (x0: Double, y0: Double, x1: Double, y1: Double)?
        var bestArea = 0.0
        var bw = 0.8 * space
        while bw <= widest {
            var bh = 0.7 * space
            while bh <= tallest {
                for lift in [-0.1, 0.0, 0.1, 0.2] {
                    // The tip the stem meets, and the corner opposite.
                    let tipRow = Double(tipY) + (up ? -lift : lift) * space
                    let x0 = up ? Double(side) - bw : Double(side)
                    let x1 = up ? Double(side) : Double(side) + bw
                    let y0 = up ? tipRow : tipRow - bh
                    let y1 = up ? tipRow + bh : tipRow
                    // The largest box whose diagonals are both ink: a smaller
                    // one inside the x has ink along them too.
                    guard bw * bh > bestArea, inked(x0, y0, x1, y1), inked(x0, y1, x1, y0) else { continue }
                    // The pockets between the arms, a fifth of the way in
                    // from each side, are paper.
                    let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
                    guard look(cx, y0 + 0.2 * bh) != 1, look(cx, y1 - 0.2 * bh) != 1,
                          look(x0 + 0.2 * bw, cy) != 1, look(x1 - 0.2 * bw, cy) != 1 else { continue }
                    best = (x0, y0, x1, y1)
                    bestArea = bw * bh
                }
                bh += 2
            }
            bw += 2
        }
        guard let best else { return nil }
        var head = PixelHead(kind: .x, x0: Int(best.x0.rounded()), x1: Int(best.x1.rounded()),
                             y0: Int(best.y0.rounded()), y1: Int(best.y1.rounded()), centreY: (best.y0 + best.y1) / 2)
        head.stemUp = up
        return head
    }
}
