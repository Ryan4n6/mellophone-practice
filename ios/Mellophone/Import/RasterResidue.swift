import CoreGraphics
import Foundation

/// A glyph found in the pixels, in pixel coordinates, placed where Leland
/// would put its origin.
struct PixelGlyph {
    let scalar: UInt32
    let x: Double
    let y: Double
}

/// A path found in the pixels: a beam, a tie, an end cap.
struct PixelShape {
    let points: [(x: Double, y: Double)]
    let filled: Bool
    let curved: Bool
}

/// What is left on a page once its staff lines, noteheads, stems and
/// barlines are out, one piece of ink at a time, measured in staff spaces.
struct ResidueBlob {
    let blob: InkBlob
    let label: Int32
    let staff: PixelStaff
    let w: Double, h: Double, fill: Double
    /// The deepest point, in spaces.
    let depth: Double
    /// Enclosed paper, in square spaces.
    let holes: Double
    /// Middle of the blob in steps above the bottom line (half spaces).
    let step: Double
}

extension RasterRecognizer {

    @_optimize(speed) static func residue(original: InkBitmap, clean: InkBitmap, heads: [PixelHead], strokes: [PixelStroke], stems: Set<Int>,
                        barlines: [PixelStroke], staves: [PixelStaff], tall: [InkBlob],
                        depth: [Float]) -> (glyphs: [PixelGlyph], text: [PixelGlyph], paths: [PixelShape]) {
        let blobs = residueBlobs(clean: clean, heads: heads, strokes: strokes, stems: stems,
                                 barlines: barlines, staves: staves, depth: depth)
        var glyphs: [PixelGlyph] = []
        /// Digits a vector page would carry in a text font: tuplet numbers.
        var textGlyphs: [PixelGlyph] = []
        var paths: [PixelShape] = []
        let stemStrokes = stems.map { strokes[$0] }
        let loose = strokes.enumerated().filter { !stems.contains($0.offset) }.map(\.element)
        var used = Set<Int>()
        /// Multi-bar rests found, by their staff's top row and x span, for
        /// their counts.
        var multiRests: [(staff: PixelStaff, x0: Int, x1: Int)] = []

        for (index, r) in blobs.enumerated() {
            let b = r.blob, staff = r.staff, space = staff.space
            let inStaff = r.step >= -1.5 && r.step <= 9.5
            // Uprights inside this blob, the strokes of an accidental.
            let uprights = loose.filter { $0.x0 >= b.x0 - 1 && $0.x1 <= b.x1 + 1 && $0.y0 >= b.y0 - 1 && $0.y1 <= b.y1 + 1 }

            // A clef: as tall as two staves' worth of space, at the head.
            if r.h >= 5, r.w <= 3.5, Double(b.x0) <= Double(staff.x0) + 4 * space {
                glyphs.append(PixelGlyph(scalar: 0xE050, x: Double(b.x0), y: staff.lineRows[3]))
                used.insert(index); continue
            }

            // Accidentals: a hole and one or two uprights, about two and a half
            // spaces tall. Measured on Leland and Opus: flat 2.41 to 2.55 high
            // with its hole low, natural 2.61 to 2.75 and sharp 2.68 with the
            // hole in the middle; the two uprights of a natural are offset by a
            // third of its height and a sharp's are not.
            if inStaff || r.step > -6, r.holes >= 0.1, r.holes <= 0.45, r.h >= 1.9, r.h <= 3.3, r.w >= 0.45, r.w <= 1.4,
               let hole = largestHole(in: b, label: r.label, clean: clean, blobs: blobs) {
                let holeAt = (hole.cy - Double(b.y0)) / Double(b.height)
                let x = Double(b.x0)
                if holeAt >= 0.6, uprights.count >= 1 {
                    glyphs.append(PixelGlyph(scalar: 0xE260, x: x, y: hole.cy))       // flat
                    used.insert(index); continue
                }
                if holeAt > 0.3, holeAt < 0.7, uprights.count >= 2 {
                    let sorted = uprights.sorted { $0.x < $1.x }
                    let offset = abs(Double(sorted.first!.y0 - sorted.last!.y0)) / Double(b.height)
                    glyphs.append(PixelGlyph(scalar: offset >= 0.18 ? 0xE261 : 0xE262, x: x, y: hole.cy))
                    used.insert(index); continue
                }
            }

            // A flat the staff lines have damaged: PEAK's key signature sets
            // its flats on and between lines, and taking the lines out opened
            // one bowl and cut another from its stem. Either way an upright
            // as tall as a flat stands at the left with the bowl at its foot,
            // and the note it flattens is where the bowl is.
            if r.step > -6, r.h >= 2.0, r.h <= 2.8, r.holes < 0.1,
               let stem = uprights.first(where: { $0.x0 - b.x0 <= 2 && Double($0.length) >= 0.8 * Double(b.height) }) {
                if r.w >= 0.7, r.w <= 1.3 {
                    glyphs.append(PixelGlyph(scalar: 0xE260, x: Double(b.x0), y: Double(b.y1) - 0.5 * space))
                    used.insert(index); continue
                }
                if r.w <= 0.45, let bowl = blobs.indices.first(where: { j in
                    let o = blobs[j]
                    return j != index && !used.contains(j) && o.w >= 0.4 && o.w <= 1.0 && o.h >= 0.7 && o.h <= 1.5
                        && o.blob.x0 >= stem.x0 && Double(o.blob.x0 - stem.x1) <= 0.2 * space
                        && abs(Double(o.blob.y1 - b.y1)) <= 0.3 * space
                }) {
                    glyphs.append(PixelGlyph(scalar: 0xE260, x: Double(b.x0), y: Double(blobs[bowl].blob.y0 + blobs[bowl].blob.y1) / 2))
                    used.formUnion([index, bowl]); continue
                }
            }

            // A dot: round, about four tenths of a space.
            if r.w >= 0.28, r.w <= 0.6, r.h >= 0.28, r.h <= 0.6, abs(r.w - r.h) <= 0.15, r.fill >= 0.65 {
                let cx = Double(b.x0 + b.x1) / 2, cy = Double(b.y0 + b.y1) / 2
                // After a head and level with it, or a step over it when the
                // head is on a line: an augmentation dot.
                let dotted = heads.contains { head in
                    let gap = (Double(b.x0) - Double(head.x1)) / space
                    let rise = (head.centreY - cy) / space
                    return gap >= 0.1 && gap <= 2.5 && rise >= -0.3 && rise <= 0.8
                }
                if dotted {
                    glyphs.append(PixelGlyph(scalar: 0xE1E7, x: Double(b.x0), y: cy))
                } else if let line = barlines.min(by: { abs($0.x - cx) < abs($1.x - cx) }),
                          abs(line.x - cx) <= 2.5 * space, abs(r.step - 3) < 0.6 || abs(r.step - 5) < 0.6,
                          // A repeat's dots come in a pair, one in each middle
                          // space; a staccato by a barline is alone.
                          blobs.contains(where: { other in
                              abs(Double(other.blob.x0 - b.x0)) <= 0.3 * space && abs(abs(other.step - r.step) - 2) < 0.6
                                  && other.w <= 0.6 && other.h <= 0.6
                          }) {
                    glyphs.append(PixelGlyph(scalar: 0xE044, x: Double(b.x0), y: cy))
                } else {
                    // Neither: a staccato, or the full stop of an ending's
                    // "1." or a dotted tempo note, which the later passes
                    // look for.
                    continue
                }
                used.insert(index); continue
            }

            // Rests, inside the staff. A whole rest hangs from the fourth line
            // and a half rest sits on the middle one; they are the same slab.
            if inStaff, r.w >= 0.9, r.w <= 1.8, r.h >= 0.3, r.h <= 0.8, r.fill >= 0.8 {
                let hangs = abs(Double(b.y0) - staff.lineRows[1]) <= abs(Double(b.y1) - staff.lineRows[2])
                glyphs.append(PixelGlyph(scalar: hangs ? 0xE4E3 : 0xE4E4, x: Double(b.x0), y: staff.lineRows[2]))
                used.insert(index); continue
            }
            // Flags, beams and ties.
            if let shape = linework(r, index: index, heads: heads, strokes: strokes, clean: clean, glyphs: &glyphs) {
                if shape.count == 3 { multiRests.append((staff, b.x0, b.x1)) }
                paths.append(contentsOf: shape)
                used.insert(index); continue
            }
            let tipped = stemStrokes.contains { stem in
                (Double(b.x0) - stem.x) / space >= -0.4 && (Double(b.x0) - stem.x) / space <= 0.5
                    && (abs(Double(b.y0 - stem.y0)) <= 0.6 * space || abs(Double(b.y1 - stem.y1)) <= 0.6 * space)
            }
            // Centred in the staff: a rest is printed about the middle line.
            // The 1 of a bar rest's 13, sitting down into the top space, is
            // an eighth rest's size.
            if r.step >= 2, r.step <= 6.5, !tipped, r.holes < 0.05, r.depth >= 0.2, r.w >= 0.7, r.w <= 1.4 {
                // Quarter rest, measured 2.94 to 3.13 high; eighth 1.84 to 1.90.
                if r.h >= 2.4, r.h <= 3.5, r.fill >= 0.33 {
                    glyphs.append(PixelGlyph(scalar: 0xE4E5, x: Double(b.x0), y: staff.lineRows[2]))
                    used.insert(index); continue
                }
                if r.h >= 1.4, r.h < 2.4 {
                    glyphs.append(PixelGlyph(scalar: 0xE4E6, x: Double(b.x0), y: staff.lineRows[2]))
                    used.insert(index); continue
                }
            }
        }
        glyphs += restDots(blobs: blobs, used: &used, rests: glyphs)
        textGlyphs += tempoMarks(blobs: blobs, used: &used, clean: clean)
        let endings = endingBrackets(blobs: blobs, used: &used, clean: clean)
        textGlyphs += endings.glyphs
        paths += endings.paths
        let tupletMarks = tuplets(blobs: blobs, used: &used, clean: clean, beams: paths.filter { $0.filled && $0.points.count == 5 })
        textGlyphs += tupletMarks.glyphs
        paths += tupletMarks.paths
        glyphs += timeSignatures(blobs: blobs, used: &used, clean: clean, original: original, staves: staves)
        glyphs += restCounts(multiRests, blobs: blobs, used: &used, clean: clean, original: original, staves: staves)
        return (glyphs, textGlyphs, paths)
    }

    /// Time signature digits: two stacked, each filling half the staff,
    /// the top one from the top line to the middle and the bottom one from
    /// the middle to the bottom line. An eighth rest is the same size but
    /// sits across the middle line and has no partner.
    @_optimize(speed) static func timeSignatures(blobs: [ResidueBlob], used: inout Set<Int>, clean: InkBitmap,
                               original: InkBitmap, staves: [PixelStaff]) -> [PixelGlyph] {
        var halves: [(index: Int, top: Bool, box: (x0: Int, y0: Int, x1: Int, y1: Int), staff: PixelStaff)] = []
        for (index, r) in blobs.enumerated() where !used.contains(index) {
            let b = r.blob, staff = r.staff, space = staff.space
            guard r.w >= 0.8, r.w <= 2.3, r.depth >= 0.2 else { continue }
            let near = { (a: Double, b: Double) in abs(a - b) <= 0.35 * space }
            if near(Double(b.y0), staff.top), near(Double(b.y1), staff.lineRows[2]) {
                halves.append((index, true, (b.x0, b.y0, b.x1, b.y1), staff))
            } else if near(Double(b.y0), staff.lineRows[2]), near(Double(b.y1), staff.bottom) {
                halves.append((index, false, (b.x0, b.y0, b.x1, b.y1), staff))
            } else if near(Double(b.y0), staff.top), near(Double(b.y1), staff.bottom) {
                // The pair touching, read as one blob: cut at the middle line.
                let middle = Int(staff.lineRows[2].rounded())
                halves.append((index, true, (b.x0, b.y0, b.x1, middle - 1), staff))
                halves.append((index, false, (b.x0, middle + 1, b.x1, b.y1), staff))
            }
        }
        var out: [PixelGlyph] = []
        for top in halves where top.top {
            guard let bottom = halves.first(where: { !$0.top && abs($0.box.x0 - top.box.x0) <= Int(0.6 * top.staff.space)
                && $0.staff.top == top.staff.top }) else { continue }
            let lift = lifted(original, staves: staves)
            guard let upper = DigitReader.read(lift, box: top.box), let lower = DigitReader.read(lift, box: bottom.box),
                  upper.digit > 0, [1, 2, 4, 8].contains(lower.digit) else {
                Log.score.error("[RASTER] a time signature at x \(top.box.x0, privacy: .public) did not read as one, dropped")
                continue
            }
            Log.score.info("[RASTER] time signature \(upper.digit, privacy: .public)/\(lower.digit, privacy: .public) at x \(top.box.x0, privacy: .public)")
            out.append(PixelGlyph(scalar: 0xE080 + UInt32(upper.digit), x: Double(top.box.x0), y: Double(top.box.y0 + top.box.y1) / 2))
            out.append(PixelGlyph(scalar: 0xE080 + UInt32(lower.digit), x: Double(bottom.box.x0), y: Double(bottom.box.y0 + bottom.box.y1) / 2))
            used.insert(top.index); used.insert(bottom.index)
        }
        return out
    }

    /// The page with each staff line kept only where something crosses it,
    /// carried on both sides: a 4 standing on the top line keeps its foot
    /// and loses the line.
    @_optimize(speed) static func lifted(_ bitmap: InkBitmap, staves: [PixelStaff]) -> InkBitmap {
        var out = bitmap
        for staff in staves {
            let half = Int((staff.thickness / 2).rounded(.up)) + 1
            for row in staff.lineRows {
                let centre = Int(row.rounded())
                for x in staff.x0...staff.x1 where !(bitmap.at(x, centre - half - 1) && bitmap.at(x, centre + half + 1)) {
                    for y in (centre - half)...(centre + half) where y >= 0 && y < bitmap.height { out.ink[y * bitmap.width + x] = 0 }
                }
            }
        }
        return out
    }

    /// A multi-bar rest's count: the digits over the middle of the bar,
    /// above the staff. Placed where ScoreBuilder looks for them, centred
    /// on the bar at step 10.
    @_optimize(speed) static func restCounts(_ rests: [(staff: PixelStaff, x0: Int, x1: Int)], blobs: [ResidueBlob],
                           used: inout Set<Int>, clean: InkBitmap, original: InkBitmap,
                           staves: [PixelStaff]) -> [PixelGlyph] {
        var out: [PixelGlyph] = []
        for rest in rests {
            let space = rest.staff.space, centre = Double(rest.x0 + rest.x1) / 2
            let candidates = blobs.indices.filter { i in
                let b = blobs[i].blob
                return !used.contains(i) && blobs[i].staff.top == rest.staff.top
                    // Over the staff, or sitting down into its top space the
                    // way Finale sets it on the ePrint in #49.
                    && Double(b.y0) < rest.staff.top && Double(b.y1) <= rest.staff.top + 0.8 * space
                    && Double(b.y1) >= rest.staff.top - 3.5 * space
                    && blobs[i].h >= 0.8 && blobs[i].h <= 2.5 && abs(Double(b.x0 + b.x1) / 2 - centre) <= 2.0 * space
                    && (DigitReader.read(clean, box: (b.x0, b.y0, b.x1, b.y1))?.distance ?? 1) <= 0.1
            }.sorted { blobs[$0].blob.x0 < blobs[$1].blob.x0 }
            // The count is one row of digits on one baseline, the row nearest
            // the staff: Florida's tempo mark sits over its first rest and
            // its "8" read into a count of 86.
            guard let lowest = candidates.map({ blobs[$0].blob.y1 }).max() else { continue }
            let digits = candidates.filter { Double(lowest - blobs[$0].blob.y1) <= 0.25 * space }
            let read = digits.compactMap { i -> Int? in
                let b = blobs[i].blob
                return DigitReader.read(clean, box: (b.x0, b.y0, b.x1, b.y1))?.digit
            }
            guard read.count == digits.count else { continue }
            Log.score.info("[RASTER] multi-bar rest of \(read.map(String.init).joined(), privacy: .public) at x \(rest.x0, privacy: .public)")
            let y = rest.staff.top - space
            for (n, digit) in read.enumerated() {
                let x = centre + (Double(n) - Double(read.count) / 2) * 0.9 * space
                out.append(PixelGlyph(scalar: 0xE080 + UInt32(digit), x: x, y: y))
            }
            used.formUnion(digits)
        }
        return out
    }

    /// A flag on a stem tip, a beam across stem tips, a multi-bar rest's bar,
    /// or a tie: the pieces that are lines rather than glyphs. Returns the
    /// paths to emit, or nil when the blob is none of them.
    @_optimize(speed) static func linework(_ r: ResidueBlob, index: Int, heads: [PixelHead], strokes: [PixelStroke],
                         clean: InkBitmap, glyphs: inout [PixelGlyph]) -> [PixelShape]? {
        let b = r.blob, staff = r.staff, space = staff.space
        // Columns: the ink runs in each, in this blob only.
        var runs: [[(y0: Int, y1: Int)]] = []
        for x in b.x0...b.x1 {
            var column: [(y0: Int, y1: Int)] = []
            var y = b.y0
            while y <= b.y1 {
                if clean.at(x, y) {
                    let start = y
                    while y <= b.y1, clean.at(x, y) { y += 1 }
                    column.append((start, y - 1))
                } else { y += 1 }
            }
            runs.append(column)
        }
        let single = Double(runs.filter { $0.count == 1 }.count) / Double(max(runs.count, 1))
        let thickness = runs.compactMap { $0.count == 1 ? Double($0[0].y1 - $0[0].y0 + 1) : nil }.sorted()
        let medianThick = thickness.isEmpty ? 0 : thickness[thickness.count / 2] / space

        // The stems whose tips this blob reaches, with their heads.
        let tips: [(stroke: PixelStroke, head: PixelHead, tipY: Int)] = heads.compactMap { head in
            guard let k = head.stem else { return nil }
            let stroke = strokes[k]
            let tipY = head.stemUp ? stroke.y0 : stroke.y1
            // Within reach of the tip: a sixteenth's second beam sits most of
            // a space in from it, which a reach of 0.6 missed on PEAK.
            guard stroke.x >= Double(b.x0) - 0.4 * space, stroke.x <= Double(b.x1) + 0.4 * space,
                  Double(tipY) >= Double(b.y0) - 1.3 * space, Double(tipY) <= Double(b.y1) + 1.3 * space else { return nil }
            return (stroke, head, tipY)
        }
        var seen = Set<Int>()
        let stemsHere = tips.filter { seen.insert($0.stroke.x0).inserted }

        // A multi-bar rest: a thick bar on the middle line, with its end
        // caps, many spaces wide and touching no stem.
        if stemsHere.isEmpty, r.w >= 2.5, abs(r.step - 4) <= 0.6, r.depth >= 0.2 {
            let top = staff.lineRows[1], bottom = staff.lineRows[3]
            let left = Double(b.x0) + 0.05 * space, right = Double(b.x1) - 0.05 * space
            return [PixelShape(points: [(left, bottom), (left, top)], filled: false, curved: false),
                    PixelShape(points: [(right, bottom), (right, top)], filled: false, curved: false),
                    PixelShape(points: [(left, staff.lineRows[2] - 0.25 * space), (right, staff.lineRows[2] - 0.25 * space),
                                        (right, staff.lineRows[2] + 0.25 * space), (left, staff.lineRows[2] + 0.25 * space),
                                        (left, staff.lineRows[2] - 0.25 * space)], filled: true, curved: false)]
        }

        // A beam: a slab a third to two thirds of a space thick across the
        // tips of two stems, or a short one off a single stem.
        // Off a single stem a beam is a short level stub, solid; a flag
        // there is tall and mostly paper (measured fill 0.13 to 0.24).
        if !stemsHere.isEmpty, r.w >= 0.8, medianThick >= 0.3, medianThick <= 0.8, single >= 0.6,
           r.depth >= 0.15, stemsHere.count >= 2 || (r.w <= 2.5 && r.h <= 0.9 && r.fill >= 0.5) {
            func middle(_ column: Int) -> Double {
                let c = runs[column]
                let run = c.max { ($0.y1 - $0.y0) < ($1.y1 - $1.y0) }!
                return Double(run.y0 + run.y1) / 2
            }
            let firstColumn = runs.firstIndex { !$0.isEmpty }!, lastColumn = runs.lastIndex { !$0.isEmpty }!
            let x0 = Double(b.x0 + firstColumn), x1 = Double(b.x0 + lastColumn)
            let half = medianThick * space / 2
            let yl = middle(min(firstColumn + 2, lastColumn)), yr = middle(max(lastColumn - 2, firstColumn))
            return [PixelShape(points: [(x0, yl - half), (x1, yr - half), (x1, yr + half), (x0, yl + half), (x0, yl - half)],
                               filled: true, curved: false)]
        }

        // A flag: hangs off one stem tip, a hook or two, and touches it. A
        // triplet's 3 printed by a stem's end is the same size and a little
        // way off it, and was read as a double flag sixteen times on PEAK.
        if stemsHere.count == 1, r.h >= 1.2, r.h <= 3.8, r.w >= 0.5, r.w <= 1.7,
           touches(r, stem: stemsHere[0].stroke, tipY: stemsHere[0].tipY, clean: clean) {
            let tip = stemsHere[0]
            let count = r.holes >= 0.08 || r.fill >= 0.3 ? 2 : 1
            let up = tip.head.stemUp
            let scalar: UInt32 = up ? (count == 1 ? 0xE240 : 0xE242) : (count == 1 ? 0xE241 : 0xE243)
            // Where ScoreBuilder measured Opus's flags: five half spaces off
            // the head, on the stem.
            glyphs.append(PixelGlyph(scalar: scalar, x: tip.stroke.x,
                                     y: tip.head.centreY + (up ? -2.5 : 2.5) * space))
            return []
        }

        // A tie or a slur: one thin curve, wider than a notehead.
        if r.w >= 1.2, r.depth <= 0.22, single >= 0.8, r.h <= 0.6 * r.w {
            let firstColumn = runs.firstIndex { !$0.isEmpty }!, lastColumn = runs.lastIndex { !$0.isEmpty }!
            let mid = (firstColumn + lastColumn) / 2
            func centre(_ c: Int) -> Double? { runs[c].first.map { Double($0.y0 + $0.y1) / 2 } }
            guard let yl = centre(firstColumn), let yr = centre(lastColumn), let ym = centre(mid) else { return nil }
            let sag = abs(ym - (yl + yr) / 2) / space
            guard sag >= 0.1 else { return nil }
            // Bent all along, the way an arc is: a quarter of the way in, an
            // arc is three quarters as far off its chord as at the middle.
            // A tuplet's bracket is a straight line between two hooks and is
            // as far off at a quarter as at the middle; read as a tie, every
            // bracket on PEAK was one.
            let quarter = firstColumn + (lastColumn - firstColumn) / 4, threeQuarters = firstColumn + 3 * (lastColumn - firstColumn) / 4
            guard let yq = centre(quarter), let yt = centre(threeQuarters) else { return nil }
            func off(_ y: Double, at fraction: Double) -> Double { abs(y - (yl + (yr - yl) * fraction)) }
            let middle = off(ym, at: 0.5)
            guard middle > 0, off(yq, at: 0.25) / middle <= 0.92, off(yt, at: 0.75) / middle <= 0.92 else { return nil }
            return [PixelShape(points: [(Double(b.x0 + firstColumn), yl), (Double(b.x0 + lastColumn), yr)],
                               filled: false, curved: true)]
        }
        return nil
    }

    /// Whether a blob's own ink meets a stem within half a space of its tip.
    @_optimize(speed) static func touches(_ r: ResidueBlob, stem: PixelStroke, tipY: Int, clean: InkBitmap) -> Bool {
        let reach = Int(0.5 * r.staff.space)
        let low = max(r.blob.y0, tipY - reach), high = min(r.blob.y1, tipY + reach)
        guard low <= high else { return false }
        for y in low...high {
            for x in (stem.x0 - 1)...(stem.x1 + 2) where clean.at(x, y) {
                if x >= r.blob.x0 && x <= r.blob.x1 { return true }
            }
        }
        return false
    }

    /// A dot after a rest: round, in the space above the middle line, just
    /// right of a rest. The rests are found in the same pass as dots, so this
    /// looks again once they all are.
    @_optimize(speed) static func restDots(blobs: [ResidueBlob], used: inout Set<Int>, rests: [PixelGlyph]) -> [PixelGlyph] {
        var out: [PixelGlyph] = []
        let restGlyphs = rests.filter { (0xE4E3...0xE4E7).contains($0.scalar) }
        for (index, r) in blobs.enumerated() where !used.contains(index) {
            guard r.w >= 0.28, r.w <= 0.6, r.h >= 0.28, r.h <= 0.6, abs(r.w - r.h) <= 0.15, r.fill >= 0.65,
                  r.step >= 2, r.step <= 7 else { continue }
            let space = r.staff.space
            guard restGlyphs.contains(where: { rest in
                let gap = (Double(r.blob.x0) - rest.x) / space
                return gap >= 0.75 && gap <= 2.5 && abs(rest.y - Double(r.blob.y0 + r.blob.y1) / 2) <= 2 * space
            }) else { continue }
            out.append(PixelGlyph(scalar: 0xE1E7, x: Double(r.blob.x0), y: Double(r.blob.y0 + r.blob.y1) / 2))
            used.insert(index)
        }
        return out
    }

    /// 1st and 2nd endings (#46 on a picture): a thin bracket over the
    /// staff, a hook down at its left end and maybe its right, with "1." or
    /// "2." inside by the left hook. Emitted as a vector page draws one, an
    /// open path up the hook and along the top, with the number and its dot
    /// as text on the hook's foot, so RepeatMarks reads it unchanged.
    @_optimize(speed) static func endingBrackets(blobs: [ResidueBlob], used: inout Set<Int>, clean: InkBitmap)
        -> (glyphs: [PixelGlyph], paths: [PixelShape]) {
        var glyphs: [PixelGlyph] = [], paths: [PixelShape] = []
        for (index, r) in blobs.enumerated() where !used.contains(index) {
            let b = r.blob, staff = r.staff, space = staff.space
            // Over the staff, its foot a space or so above the top line:
            // measured 2.19 half spaces on Florida and the fixture, the hook
            // 4.40 tall.
            let footRise = (staff.top - Double(b.y1)) / space
            guard footRise >= 0.3, footRise <= 3, r.h >= 1.4, r.h <= 3.2, r.w >= 2, r.depth <= 0.15 else { continue }
            // The top: one row of ink across most of the width, at the top.
            let topRun = (b.x0...b.x1).filter { x in (b.y0...min(b.y0 + 3, b.y1)).contains { clean.at(x, $0) } }.count
            guard Double(topRun) >= 0.85 * Double(b.width) else { continue }
            // The left hook: ink down the first columns most of the height.
            let hook = (b.y0...b.y1).filter { y in (b.x0...min(b.x0 + 3, b.x1)).contains { clean.at($0, y) } }.count
            guard Double(hook) >= 0.8 * Double(b.height) else { continue }
            let rightHook = (b.y0...b.y1).filter { y in (max(b.x1 - 3, b.x0)...b.x1).contains { clean.at($0, y) } }.count
            let closed = Double(rightHook) >= 0.8 * Double(b.height)
            // The number inside, by the left hook, and its dot.
            let inside = blobs.indices.filter { j in
                let o = blobs[j].blob
                return j != index && !used.contains(j) && o.x0 > b.x0 && Double(o.x0 - b.x0) <= 3 * space
                    && o.y0 > b.y0 && o.y1 <= b.y1 + Int(0.3 * space)
            }.sorted { blobs[$0].blob.x0 < blobs[$1].blob.x0 }
            let digits = inside.filter { blobs[$0].h >= 0.6 }
            guard let first = digits.first, let read = DigitReader.read(clean, box: (blobs[first].blob.x0, blobs[first].blob.y0,
                                                                                   blobs[first].blob.x1, blobs[first].blob.y1)),
                  (1...4).contains(read.digit), read.margin >= 0.005,
                  let dot = inside.first(where: { blobs[$0].w <= 0.5 && blobs[$0].h <= 0.5 && blobs[$0].blob.x0 > blobs[first].blob.x1 }) else { continue }
            let foot = Double(b.y1), top = Double(b.y0)
            var points: [(x: Double, y: Double)] = [(Double(b.x0), foot), (Double(b.x0), top), (Double(b.x1), top)]
            if closed { points.append((Double(b.x1), foot)) }
            paths.append(PixelShape(points: points, filled: false, curved: false))
            glyphs.append(PixelGlyph(scalar: 0x30 + UInt32(read.digit), x: Double(blobs[first].blob.x0), y: foot))
            glyphs.append(PixelGlyph(scalar: 0x2E, x: Double(blobs[dot].blob.x0), y: foot))
            used.formUnion([index, first, dot])
            Log.score.info("[RASTER] ending \(read.digit, privacy: .public). at x \(b.x0, privacy: .public), \(closed ? "closed" : "open", privacy: .public)")
        }
        return (glyphs, paths)
    }

    /// Metronome marks (#41 on a picture): a little note, "=", and a number,
    /// over a staff. Emitted as the text glyphs a vector page carries, on the
    /// number's baseline, so TempoMarks reads them as it reads any chart:
    /// the note as SMuFL's metronome quarter (or half), a dot when there is
    /// one, "=", the digits.
    @_optimize(speed) static func tempoMarks(blobs: [ResidueBlob], used: inout Set<Int>, clean: InkBitmap) -> [PixelGlyph] {
        var out: [PixelGlyph] = []
        // The bars of an "=": short, thin, solid, one over the other.
        let bars = blobs.indices.filter { i in
            let r = blobs[i]
            // Measured: 0.11 thick on the ePrint, 0.29 to 0.32 in Florida's
            // bold mark.
            return !used.contains(i) && (r.step > 9 || r.step < -1) && r.h <= 0.4 && r.w >= 0.4 && r.w <= 1.4 && r.fill >= 0.75
        }
        var taken = Set<Int>()
        for upper in bars where !taken.contains(upper) {
            let a = blobs[upper].blob, space = blobs[upper].staff.space
            guard let lower = bars.first(where: { j in
                let b = blobs[j].blob
                let gap = Double(b.y0 - a.y1) / space
                return j != upper && !taken.contains(j) && abs(Double(b.x0 - a.x0)) <= 0.2 * space
                    && abs(Double(b.width - a.width)) <= 0.25 * space && gap >= 0.1 && gap <= 0.6
            }) else { continue }
            let b = blobs[lower].blob
            let middle = Double(a.y0 + b.y1) / 2
            // The digits after it, each starting near where the last ended.
            var digits: [Int] = []
            var right = b.x1
            var reads: [(index: Int, digit: Int)] = []
            while let next = blobs.indices.filter({ i in
                let r = blobs[i]
                return !used.contains(i) && !reads.contains(where: { $0.index == i }) && r.blob.x0 > right
                    && Double(r.blob.x0 - right) <= (reads.isEmpty ? 1.6 : 0.6) * space
                    && Double(r.blob.y0) < middle && Double(r.blob.y1) > middle && r.h >= 0.6 && r.h <= 2.0
            }).min(by: { blobs[$0].blob.x0 < blobs[$1].blob.x0 }) {
                let box = blobs[next].blob
                // A wrong tempo is worse than none (#41): the student would
                // trust it. A digit that is not plainly itself ends the number.
                guard let read = DigitReader.read(clean, box: (box.x0, box.y0, box.x1, box.y1)),
                      read.distance <= 0.15, read.margin >= 0.005 else { break }
                reads.append((next, read.digit))
                digits.append(read.digit)
                right = box.x1
            }
            let number = digits.reduce(0) { $0 * 10 + $1 }
            guard (20...400).contains(number) else { continue }
            // The note before it.
            guard let note = blobs.indices.filter({ i in
                let r = blobs[i]
                // Further off when dotted: reader-traps' "♩. = 80" has its dot
                // between the note and the "=".
                return !used.contains(i) && r.blob.x1 < a.x0 && Double(a.x0 - r.blob.x1) <= 2.4 * space
                    && r.h >= 0.9 && r.h <= 2.6 && Double(r.blob.y1) >= middle
            }).max(by: { blobs[$0].blob.x1 < blobs[$1].blob.x1 }) else { continue }
            let baseline = Double(reads.map { blobs[$0.index].blob.y1 }.max()!)
            // The note is read as a quarter, dotted only when a round dot sits
            // between it and the "=" at the height of its head, which stands
            // on the number's baseline. Telling a half from a quarter at this
            // size was tried and was wrong five times in thirteen: the note
            // runs into the word before it ("Dramatically" on the ePrint) or
            // the hole of a letter looks like a hollow head, and a wrong note
            // plays the passage at double or half speed, worse than the
            // student's own number (#41). Every mark on our charts and Sam's
            // counts in quarters or dotted quarters.
            out.append(PixelGlyph(scalar: 0xECA5, x: Double(blobs[note].blob.x0), y: baseline))
            if let dot = blobs.indices.first(where: { i in
                let r = blobs[i]
                let cy = Double(r.blob.y0 + r.blob.y1) / 2
                return !used.contains(i) && r.blob.x0 > blobs[note].blob.x1 && r.blob.x1 < a.x0
                    && r.w >= 0.2 && r.w <= 0.5 && r.h >= 0.2 && r.h <= 0.5 && abs(r.w - r.h) <= 0.12 && r.fill >= 0.6
                    && cy <= baseline && cy >= baseline - 1.0 * space
            }) {
                out.append(PixelGlyph(scalar: 0xECB7, x: Double(blobs[dot].blob.x0), y: baseline))
                used.insert(dot)
            }
            out.append(PixelGlyph(scalar: 0x3D, x: Double(a.x0), y: baseline))
            for read in reads {
                out.append(PixelGlyph(scalar: 0x30 + UInt32(read.digit), x: Double(blobs[read.index].blob.x0), y: baseline))
                used.insert(read.index)
            }
            used.formUnion([upper, lower, note])
            taken.formUnion([upper, lower])
            Log.score.info("[RASTER] tempo mark = \(number, privacy: .public) at x \(a.x0, privacy: .public)")
        }
        return out
    }

    /// Tuplet numbers: a lone 3, 5, 6 or 7 over or under the staff, by a
    /// beam or between the two halves of a bracket. Emitted as text digits on
    /// their baseline, the way a vector page carries them, with the bracket's
    /// halves as the short lines ScoreBuilder looks for either side.
    @_optimize(speed) static func tuplets(blobs: [ResidueBlob], used: inout Set<Int>, clean: InkBitmap,
                        beams: [PixelShape]) -> (glyphs: [PixelGlyph], paths: [PixelShape]) {
        var glyphs: [PixelGlyph] = [], paths: [PixelShape] = []
        for (index, r) in blobs.enumerated() where !used.contains(index) {
            let b = r.blob, space = r.staff.space
            guard r.step < -1.5 || r.step > 9.5, r.h >= 0.6, r.h <= 1.6, r.w >= 0.35, r.w <= 1.2 else { continue }
            let read0 = DigitReader.read(clean, box: (b.x0, b.y0, b.x1, b.y1))
            // Close matches only: PEAK prints a bar number over and under
            // every bar, and its 5s, 6s and 7s match a tuplet's digit at
            // 0.06 to 0.17. A real triplet's 3 matched at 0.03.
            guard let read = read0, [3, 5, 6, 7].contains(read.digit),
                  read.distance <= 0.05 else { continue }
            let cx = Double(b.x0 + b.x1) / 2, cy = Double(b.y0 + b.y1) / 2
            // Its bracket: thin straight pieces level with it, either side.
            // A bracket half is a long thin line with a hook, mostly paper
            // (measured on PEAK: 3.2 spaces long, 1.0 to 1.3 high with the
            // hook and the slope, fill 0.13 to 0.16),
            // not another digit.
            func bracketPiece(_ j: Int) -> Bool {
                let o = blobs[j]
                return j != index && !used.contains(j) && o.depth <= 0.15 && o.w >= 1.2 && o.h <= 1.6 && o.fill <= 0.35
                    && abs(Double(o.blob.y0 + o.blob.y1) / 2 - cy) <= 0.8 * space
            }
            let left = blobs.indices.filter { bracketPiece($0) && abs(Double(blobs[$0].blob.x1) - Double(b.x0)) <= 1.0 * space }
            let right = blobs.indices.filter { bracketPiece($0) && abs(Double(blobs[$0].blob.x0) - Double(b.x1)) <= 1.5 * space }
            let halves = left.isEmpty || right.isEmpty ? [] : [left[0], right[0]]
            let beamed = beams.contains { beam in
                let xs = beam.points.map(\.x), ys = beam.points.map(\.y)
                return cx >= xs.min()! - space && cx <= xs.max()! + space && abs((ys.min()! + ys.max()!) / 2 - cy) <= 3 * space
            }
            guard halves.count >= 2 || beamed else { continue }
            glyphs.append(PixelGlyph(scalar: 0x30 + UInt32(read.digit), x: Double(b.x0), y: Double(b.y1)))
            used.insert(index)
            for j in halves {
                let o = blobs[j].blob
                // The line along the bracket's long side, at the end nearer
                // the number.
                let row = Double(o.y0 + o.y1) / 2
                paths.append(PixelShape(points: [(Double(o.x0), row), (Double(o.x1), row)], filled: false, curved: false))
                used.insert(j)
            }
            Log.score.info("[RASTER] tuplet \(read.digit, privacy: .public) at x \(b.x0, privacy: .public), \(halves.count, privacy: .public) bracket pieces, beamed \(beamed, privacy: .public)")
        }
        return (glyphs, paths)
    }

    /// The biggest hole inside a residue blob.
    @_optimize(speed) static func largestHole(in blob: InkBlob, label: Int32, clean: InkBitmap, blobs: [ResidueBlob]) -> PixelHole? {
        // Labelled locally: the paper inside the blob's box that the blob
        // closes off.
        let bw = blob.width + 2, bh = blob.height + 2
        var paper = InkBitmap(width: bw, height: bh, ink: [UInt8](repeating: 0, count: bw * bh), scale: 1, pageHeight: 0)
        for y in 0..<bh { for x in 0..<bw {
            let px = blob.x0 + x - 1, py = blob.y0 + y - 1
            let inside = x >= 1 && y >= 1 && x <= blob.width && y <= blob.height
            if !(inside && clean.at(px, py)) { paper.ink[y * bw + x] = 1 }
        } }
        let (_, pieces) = InkComponents.label4(paper)
        let enclosed = pieces.filter { $0.x0 > 0 && $0.y0 > 0 && $0.x1 < bw - 1 && $0.y1 < bh - 1 }
        guard let big = enclosed.max(by: { $0.count < $1.count }) else { return nil }
        return PixelHole(x0: big.x0 + blob.x0 - 1, y0: big.y0 + blob.y0 - 1, x1: big.x1 + blob.x0 - 1,
                         y1: big.y1 + blob.y0 - 1, area: big.count)
    }

    /// The page with heads, stems and barlines taken out, cut into blobs.
    @_optimize(speed) static func residueBlobs(clean: InkBitmap, heads: [PixelHead], strokes: [PixelStroke], stems: Set<Int>,
                             barlines: [PixelStroke], staves: [PixelStaff], depth: [Float]) -> [ResidueBlob] {
        var page = clean
        let w = clean.width
        // A head goes as the oval it is, a pixel larger all round. An x goes
        // as its whole box, or the ends of its arms are left as crumbs.
        for head in heads where head.kind == .x {
            for y in max(head.y0 - 1, 0)...min(head.y1 + 1, clean.height - 1) {
                for x in max(head.x0 - 1, 0)...min(head.x1 + 1, w - 1) { page.ink[y * w + x] = 0 }
            }
        }
        for head in heads where head.kind != .x {
            let cx = Double(head.x0 + head.x1) / 2, cy = head.centreY
            let space = staffOf(cy, staves).space
            let rx = Double(head.x1 - head.x0) / 2 + 1, ry = head.kind == .black
                ? Double(head.y1 - head.y0) / 2 + 1 : Double(head.y1 - head.y0) / 2 + 0.2 * space
            for y in Int(cy - ry)...Int(cy + ry) {
                for x in Int(cx - rx)...Int(cx + rx) where x >= 0 && y >= 0 && x < w && y < clean.height {
                    let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
                    if dx * dx + dy * dy <= 1 { page.ink[y * w + x] = 0 }
                }
            }
        }
        // Stems and barlines go where they are the whole of the ink across,
        // so a beam or a flag keeps the rows where it meets one.
        let uprights = stems.map { strokes[$0] } + barlines
        page = PixelStrokes.removing(uprights, from: page, slack: 2)
        let (labels, blobs) = InkComponents.label(page)
        var out: [ResidueBlob] = []
        for (index, blob) in blobs.enumerated() {
            let cy = Double(blob.y0 + blob.y1) / 2
            let staff = staffOf(cy, staves)
            let space = staff.space
            // Specks: an antialiasing crumb, the nub a removed line leaves on
            // a stem.
            guard Double(blob.count) >= 0.02 * space * space else { continue }
            guard distance(cy, staff) <= 8 * space else { continue }
            var deepest: Float = 0
            for y in blob.y0...blob.y1 {
                for x in blob.x0...blob.x1 where labels[y * w + x] == Int32(index + 1) {
                    deepest = max(deepest, depth[y * w + x])
                }
            }
            let holes = PixelHeads.enclosedPaper(in: blob, label: Int32(index + 1), labels: labels, width: w)
            out.append(ResidueBlob(blob: blob, label: Int32(index + 1), staff: staff,
                                   w: Double(blob.width) / space, h: Double(blob.height) / space,
                                   fill: Double(blob.count) / Double(blob.width * blob.height),
                                   depth: Double(deepest) / space, holes: Double(holes) / (space * space),
                                   step: (staff.bottom - cy) / (space / 2)))
        }
        return out
    }
}

