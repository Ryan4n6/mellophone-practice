import CoreGraphics
import Foundation

/// One five-line staff, in page coordinates.
///
/// Pure geometry. There is no musical vocabulary in this file at all, which is
/// what lets it be tested with made-up rectangles instead of a fixture, and what
/// keeps the question "which line is this note on" in ScoreBuilder where it
/// belongs.
struct StaffSystem {
    /// The five line centres in ascending y, which in a PDF is BOTTOM line
    /// first. PDF user space has y increasing upward and PDFGlyphReader reports
    /// raw user space, so nothing here is in screen order.
    let lineYs: [Double]
    /// The horizontal span of the staff, used to decide which glyphs belong to
    /// it when two systems overlap in y on a multi-part page.
    let xRange: ClosedRange<Double>

    /// The BOTTOM line, which is E4 under a treble clef.
    ///
    /// Named for what it is. This accessor was called `topLineY` and returned
    /// the same value, which read as the F5 line and put every pitch upside
    /// down. Measured both ways round: the treble clef glyph's origin sits 2.00
    /// steps above `lineYs[0]` in Opus and in Leland alike, and a treble clef
    /// sits on G4, the second line from the bottom.
    var bottomLineY: Double { lineYs[0] }

    /// Half the gap between adjacent lines. One diatonic step is exactly this,
    /// because a step moves a notehead from a line to the space beside it, so
    /// every pitch calculation downstream is expressed in these units.
    var halfSpace: Double { (lineYs[4] - lineYs[0]) / 8 }
}

enum StaffFitter {
    /// A staff line is long, thin and horizontal. These thresholds are in PDF
    /// points and were measured against the charts in issue #19, where lines run
    /// several hundred points wide (517.1 in PEAK mello.pdf) and no more than
    /// one point thick, while beams are under twenty wide and over three thick.
    ///
    /// The width floor is NOT the width of a staff, because MuseScore draws
    /// its staff lines once per bar. Florida's bars run 39.68 to 105 points,
    /// and at 40 the narrowest, the last bar on two of its four lines, was
    /// dropped along with every note in it (#39). A segment only becomes a
    /// staff by being five evenly spaced rules of one extent, which a ledger
    /// line (about 7 points, and never five stacked on a horn part) is not, so
    /// the floor only has to clear noise.
    private static let minimumWidth: Double = 12
    /// Admits 0 on purpose: a STROKED line has no area, so its bounds have no
    /// height at all. Sibelius strokes its staff lines and MuseScore fills them,
    /// and an implementation that requires a fill, or a thickness strictly
    /// greater than zero, finds six candidates on a PEAK mello.pdf page that has
    /// fifty and then reports "no staff found" for every chart Sam owns.
    private static let maximumThickness: Double = 2.0
    /// Spacing across the five lines of one staff must agree to this, in points.
    /// The observed variation in a real export is under 0.05.
    private static let spacingTolerance: Double = 0.4
    /// Two rules whose ends agree this closely were drawn by the same rectangle
    /// set, so they belong to the same staff. See `groupedByExtent`.
    private static let extentTolerance: Double = 1.0
    /// Two rules in one extent group closer together in y than this are the same
    /// line drawn twice, not two lines. See `collapsingDuplicates`.
    private static let duplicateEpsilon: Double = 0.5
    /// Two fits whose bottom lines agree this closely are one staff drawn in
    /// segments. See `mergingFragments`. The observed agreement is exact.
    private static let mergeTolerance: Double = 0.5

    static func systems(in paths: [PlacedPath]) -> [StaffSystem] {
        // Deliberately NOT filtering on `filled`. See maximumThickness above.
        let candidates = paths
            .filter { Double($0.bounds.width) >= minimumWidth
                && Double($0.bounds.height) <= maximumThickness }
            .sorted { $0.bounds.midY < $1.bounds.midY }

        // Group before scanning, because sorting the whole page by y interleaves
        // the staff lines with anything else long and thin that happens to sit
        // between them. See groupedByExtent.
        // Merge before sorting, and sort DESCENDING: larger y is higher on the
        // page, so systems[0] is the top staff and the document reads in order.
        var systems = mergingFragments(groupedByExtent(candidates)
            .filter { $0.count >= 5 }
            .flatMap { evenlySpacedRuns(in: collapsingDuplicates($0)) })
        systems.sort { $0.bottomLineY > $1.bottomLineY }

        if systems.isEmpty {
            // The failure that matters: a page full of long thin paths that
            // never grouped into fives means the thresholds are wrong for this
            // engraver, which is a different problem from a page with no staff
            // on it, and the counts are what tell them apart.
            Log.score.error(
                "[IMPORT] no staff systems fitted from \(candidates.count, privacy: .public) rules of \(paths.count, privacy: .public) paths")
        } else {
            Log.score.info(
                "[IMPORT] fitted \(systems.count, privacy: .public) staff systems from \(candidates.count, privacy: .public) rules, halfSpace \(systems[0].halfSpace, privacy: .public), top staff at y \(systems[0].bottomLineY, privacy: .public)")
        }
        return systems
    }

    /// Rejoins the x segments of one physical staff.
    ///
    /// `groupedByExtent` is what keeps a Sibelius multi-measure rest out of a
    /// staff, and it is also what breaks MuseScore, which emits a fresh set of
    /// five rules FOR EVERY MEASURE. Measured on the Florida chart in issue #19:
    /// 27 systems on a page that has 4, in segments 43 to 105 points wide that
    /// abut exactly. Every stage after this one reads the clef and the key
    /// signature from the head of a system, and in that state they live in a
    /// different system from the notes they govern.
    ///
    /// Two fits whose five line positions agree are the same staff whatever
    /// their x, so the merge is on `lineYs` alone and the x ranges union. It is
    /// a no-op on Sibelius, which draws each staff as one rule set: PEAK page 1
    /// fits 9 and merges to 9.
    private static func mergingFragments(_ fits: [StaffSystem]) -> [StaffSystem] {
        var merged: [StaffSystem] = []
        for fit in fits {
            guard let index = merged.firstIndex(where: {
                abs($0.bottomLineY - fit.bottomLineY) < mergeTolerance
            }) else {
                merged.append(fit)
                continue
            }
            let existing = merged[index]
            let low = min(existing.xRange.lowerBound, fit.xRange.lowerBound)
            let high = max(existing.xRange.upperBound, fit.xRange.upperBound)
            merged[index] = StaffSystem(lineYs: existing.lineYs, xRange: low...high)
        }
        return merged
    }

    /// Buckets rules that start and end at the same x.
    ///
    /// The five lines of a system are emitted as one set of rectangles, so they
    /// share an x extent exactly, and nothing else on the page does. This is the
    /// filter that separates a staff line from a multi-measure rest H-bar, which
    /// is the intruder that actually appears in Sam's charts: PEAK mello.pdf
    /// draws its H-bars 45 to 78 points wide, twice each (once stroked, once
    /// filled), sitting BETWEEN two staff lines. Sorting the page by y and
    /// taking every five consecutive rules therefore finds 6 systems on a page
    /// that has 9, because an H-bar takes a slot inside three of the staves and
    /// makes their spacing look uneven.
    ///
    /// Grouping on the extent rather than on the width alone keeps two systems
    /// of the same width but different indentation apart, which is what the
    /// first system of a piece looks like when it carries an instrument name.
    private static func groupedByExtent(_ rules: [PlacedPath]) -> [[PlacedPath]] {
        var groups: [[PlacedPath]] = []
        for rule in rules {
            let index = groups.firstIndex { group in
                guard let first = group.first else { return false }
                return abs(Double(first.bounds.minX) - Double(rule.bounds.minX)) < extentTolerance
                    && abs(Double(first.bounds.maxX) - Double(rule.bounds.maxX)) < extentTolerance
            }
            if let index { groups[index].append(rule) } else { groups.append([rule]) }
        }
        return groups
    }

    /// Keeps the first of any run of rules in one group sharing a y.
    ///
    /// Every rule in these charts is emitted twice, once as a stroke and once as
    /// a fill of the same rectangle. A duplicated line puts a zero into the gap
    /// list, so no window is ever even and a perfectly ordinary staff is
    /// reported as missing. Safe to do only AFTER grouping by extent, because
    /// two different H-bars can share a y side by side and are not duplicates.
    /// Input must be sorted by midY.
    private static func collapsingDuplicates(_ rules: [PlacedPath]) -> [PlacedPath] {
        var kept: [PlacedPath] = []
        for rule in rules {
            guard let last = kept.last,
                  Double(rule.bounds.midY) - Double(last.bounds.midY) < duplicateEpsilon
            else {
                kept.append(rule)
                continue
            }
        }
        return kept
    }

    /// Walks one group looking for five lines at an even spacing.
    ///
    /// Greedy: on a match the window advances a whole staff, on a miss it
    /// advances one rule, so a stray line costs one step of alignment and not
    /// the rest of the group.
    private static func evenlySpacedRuns(in rules: [PlacedPath]) -> [StaffSystem] {
        var systems: [StaffSystem] = []
        var i = 0
        while i + 4 < rules.count {
            let window = Array(rules[i..<(i + 5)])
            let ys = window.map { Double($0.bounds.midY) }
            let gaps = zip(ys, ys.dropFirst()).map { $1 - $0 }
            let even = (gaps.max()! - gaps.min()!) < spacingTolerance
            // The band rejects a group of five rules that are evenly spaced but
            // are not a staff: text underlines sit far apart, and anything under
            // a point apart is one thick line drawn as several.
            if even, gaps[0] > 1, gaps[0] < 30 {
                let x0 = window.map { Double($0.bounds.minX) }.min()!
                let x1 = window.map { Double($0.bounds.maxX) }.max()!
                systems.append(StaffSystem(lineYs: ys, xRange: x0...x1))
                i += 5
            } else {
                i += 1
            }
        }
        return systems
    }
}
