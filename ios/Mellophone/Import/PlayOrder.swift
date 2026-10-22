import Foundation
import OSLog

/// The bars of a part in the order a band plays them (#46).
///
/// Pure arithmetic on bar numbers, so every repeat shape is a test with no
/// page in it. The page's own numbers are kept throughout: bar 7 played the
/// second time is still bar 7, which is what the director calls it.
enum PlayOrder {

    /// Unroll `repeats` over `page`, the bars as printed.
    ///
    /// Each end repeat is taken once, or once more for every extra pass an
    /// ending before it names ("1. 2." then "3." goes round twice). It goes
    /// back to the last start repeat before it, or with none, to the bar after
    /// the last end repeat before it, or to the top. An ending is skipped on
    /// any pass it does not name, and runs to the end repeat that closes it.
    static func bars(_ page: [Int], repeats: Repeats) -> [Int] {
        guard !repeats.isEmpty, !page.isEmpty else { return page }
        let index = Dictionary(page.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }

        // Where an ending stops: at the end repeat that closes it, or just
        // before the next ending opens, whichever comes first.
        var endingEnd: [Int: Int] = [:]
        for bar in repeats.endings.keys {
            guard let start = index[bar] else { continue }
            var last = start
            while last < page.count - 1, !repeats.ends.contains(page[last]),
                  repeats.endings[page[last + 1]] == nil {
                last += 1
            }
            endingEnd[start] = last
        }

        // Where each end repeat goes back to, and how many times through it
        // makes. Decided from the page alone, before anything is played.
        var target: [Int: Int] = [:]
        var times: [Int: Int] = [:]
        for (position, bar) in page.enumerated() where repeats.ends.contains(bar) {
            let lastStart = page[...position].indices.last { repeats.starts.contains(page[$0]) }
            let lastEnd = page[..<position].indices.last { repeats.ends.contains(page[$0]) }
            target[position] = lastStart ?? lastEnd.map { $0 + 1 } ?? 0
            let named = endingEnd.filter { $0.value == position }
                .flatMap { repeats.endings[page[$0.key]] ?? [] }
            times[position] = max(2, (named.max() ?? 1) + 1)
        }

        var order: [Int] = []
        var taken: [Int: Int] = [:]
        var pass = 1
        var position = 0
        var arrivedByJump = false
        // A page that is read wrong could in principle loop; no real part
        // plays any bar more than a handful of times.
        let limit = page.count * 8
        while position < page.count, order.count < limit {
            let bar = page[position]
            if repeats.starts.contains(bar), !arrivedByJump { pass = 1 }
            arrivedByJump = false
            if let passes = repeats.endings[bar], !passes.contains(pass) {
                position = (endingEnd[position] ?? position) + 1
                continue
            }
            order.append(bar)
            if let back = target[position], (taken[position] ?? 0) < (times[position] ?? 2) - 1 {
                taken[position, default: 0] += 1
                pass += 1
                position = back
                arrivedByJump = true
                continue
            }
            // Played through a repeat already taken: whatever comes next is a
            // new section and counts its passes from one. A 2nd ending never
            // gets here, its end repeat is inside the 1st ending it skipped.
            if target[position] != nil { pass = 1 }
            position += 1
        }
        if order.count >= limit {
            Log.score.error("[REPEAT] stopped unrolling at \(limit, privacy: .public) bars; the repeats read off this page do not close")
        }
        Log.score.info("[REPEAT] \(page.count, privacy: .public) bars on the page play as \(order.count, privacy: .public): \(runs(order), privacy: .public)")
        return order
    }

    /// The bars from the first time `from` comes up to the next time `to`
    /// does after it, or to the end. A loop of the 1st ending stays two bars,
    /// and a range across a repeat goes round it the way the band does.
    static func slice(_ order: [Int], from: Int, to: Int) -> [Int] {
        guard let first = order.firstIndex(of: from) else { return [] }
        let last = order[first...].firstIndex(of: to) ?? order.count - 1
        return Array(order[first...last])
    }

    /// "7 to 38, 7 to 36, 39 to 42": runs of bars that follow each other.
    static func runs(_ order: [Int]) -> String {
        var runs: [(Int, Int)] = []
        for bar in order {
            if let last = runs.last, bar == last.1 + 1 {
                runs[runs.count - 1].1 = bar
            } else {
                runs.append((bar, bar))
            }
        }
        return runs.map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0) to \($0.1)" }.joined(separator: ", ")
    }
}
