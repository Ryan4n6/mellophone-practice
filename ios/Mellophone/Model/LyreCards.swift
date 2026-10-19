import CoreGraphics
import OSLog

/// One card of a chart on the screen: a run of the director's own lines (#43).
struct LyreCard: Equatable {
    let index: Int
    /// Indexes into `Score.systems`.
    let systems: Range<Int>
    let firstMeasure: Int
    let lastMeasure: Int
}

/// How a chart is dealt into cards, on the screen and on paper (#43).
///
/// Pure arithmetic on where the reader says each line was printed, so a card
/// that turns at the wrong bar is a test here before it is a screen.
enum LyreCards {

    /// Lines per card on the screen. Four is a lyre card; fewer is for a
    /// student who needs them bigger. More than four would not fit sideways.
    static let lineChoices = 2...4

    static func cards(_ systems: [SystemPlace], linesPerCard: Int) -> [LyreCard] {
        let lines = min(max(linesPerCard, lineChoices.lowerBound), lineChoices.upperBound)
        return stride(from: 0, to: systems.count, by: lines).enumerated().compactMap { index, start in
            let range = start..<min(start + lines, systems.count)
            let measures = systems[range].flatMap(\.bars).map(\.measure)
            guard let first = measures.min(), let last = measures.max() else {
                Log.score.error("[CARD] lines \(range.lowerBound + 1, privacy: .public) to \(range.upperBound, privacy: .public) have no bars, no card made")
                return nil
            }
            return LyreCard(index: index, systems: range, firstMeasure: first, lastMeasure: last)
        }
    }

    static func index(holding measure: Int, in cards: [LyreCard]) -> Int? {
        cards.firstIndex { $0.firstMeasure <= measure && measure <= $0.lastMeasure }
    }

    /// The rectangle of the PDF page a line is cut from, in PDF user space.
    ///
    /// Two half spaces left of the staff, because the clef starts on the
    /// staff's first pixel and anti-aliasing reaches past it; one half space
    /// round the ink everywhere else, so a dynamic or a tempo mark is not
    /// shaved. The screen and the printed card both cut from this.
    static func strip(_ system: SystemPlace) -> CGRect {
        let hs = system.halfSpace
        return CGRect(x: system.xRange.lowerBound - 2 * hs,
                      y: system.inkBottom - hs,
                      width: system.xRange.upperBound - system.xRange.lowerBound + 3 * hs,
                      height: system.inkTop - system.inkBottom + 2 * hs)
    }
}

/// Printed lyre cards for a ring flip folder (#43).
///
/// Sam's sleeve is 18.0 by 13.6 cm with a reinforced strip over its top 2.0 cm
/// for the rings (measured off the product photo, 65 of 449 pixels). A card
/// is two millimetres under the sleeve each way so it slides in, nothing is
/// printed under the ring strip, and the music is 17.0 cm wide.
enum LyreCardPrint {
    private static let pointsPerCentimetre: CGFloat = 72 / 2.54

    static let cardSize = CGSize(width: 17.8 * pointsPerCentimetre, height: 13.4 * pointsPerCentimetre)
    static let ringStrip: CGFloat = 2.2 * pointsPerCentimetre
    static let edge: CGFloat = 0.4 * pointsPerCentimetre
    static let musicWidth: CGFloat = 17.0 * pointsPerCentimetre

    /// One scale for the whole chart, so every card's staff is the same size
    /// and a student's eye does not refocus at every flip: the widest line
    /// fills the music width. Lines are dealt in reading order, as many as
    /// fit under the ring strip, and a line is never split across two cards.
    static func layout(_ systems: [SystemPlace]) -> (scale: CGFloat, cards: [Range<Int>]) {
        guard let widest = systems.map({ LyreCards.strip($0).width }).max(), widest > 0 else { return (1, []) }
        let scale = musicWidth / widest
        let room = cardSize.height - ringStrip - edge
        var cards: [Range<Int>] = []
        var start = 0, used: CGFloat = 0
        for index in systems.indices {
            let height = LyreCards.strip(systems[index]).height * scale
            if index > start, used + height > room {
                cards.append(start..<index)
                start = index
                used = 0
            }
            if height > room {
                Log.score.error("[CARD] line \(index + 1, privacy: .public) is taller than a printed card at this scale and will run off it")
            }
            used += height
        }
        if start < systems.count { cards.append(start..<systems.count) }
        Log.score.info("[CARD] \(systems.count, privacy: .public) lines print on \(cards.count, privacy: .public) cards at \(scale, format: .fixed(precision: 3), privacy: .public) of the page")
        return (scale, cards)
    }
}
