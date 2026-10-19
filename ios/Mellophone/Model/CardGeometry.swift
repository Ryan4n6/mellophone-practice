import CoreGraphics

/// Where things land on one card on the screen (#43).
///
/// A card is its lines' strips stacked top to bottom with no gap between them,
/// the director's spacing between lines being the one thing a lyre card
/// throws away. The strips keep their x as printed, so an indented first line
/// stays indented and every barline sits where the page put it. View points,
/// origin top left, y down; the page's are PDF points, y up.
struct CardGeometry {
    let systems: [SystemPlace]
    let card: LyreCard
    /// View points per PDF point.
    let scale: CGFloat
    let height: CGFloat
    private let left: CGFloat
    private let frames: [Int: CGRect]

    /// A notehead's centre is right of its glyph origin by about half its
    /// width. 1.2 half spaces is half a black head in Opus and in Leland.
    private static let headCentre: CGFloat = 1.2
    /// A box a head and a half wide and not quite two spaces tall, so a
    /// neighbouring line or space is not covered.
    private static let boxWidth: CGFloat = 3.5
    private static let boxHeight: CGFloat = 2.6
    /// A tap further than this from a head's centre is a tap on the staff.
    private static let tapReach: CGFloat = 2.5

    init(systems: [SystemPlace], card: LyreCard, width: CGFloat) {
        self.systems = systems
        self.card = card
        let strips = card.systems.map { LyreCards.strip(systems[$0]) }
        let left = strips.map(\.minX).min() ?? 0
        let right = strips.map(\.maxX).max() ?? 1
        let scale = width / max(right - left, 1)
        var frames: [Int: CGRect] = [:]
        var y: CGFloat = 0
        for (index, strip) in zip(card.systems, strips) {
            let frame = CGRect(x: (strip.minX - left) * scale, y: y,
                               width: strip.width * scale, height: strip.height * scale)
            frames[index] = frame
            y = frame.maxY
        }
        self.left = left
        self.scale = scale
        self.height = y
        self.frames = frames
    }

    /// The strip of `system` on the card, in view points. `.null` for a line
    /// that is not on this card.
    func stripFrame(_ system: Int) -> CGRect { frames[system] ?? .null }

    func point(x: Double, y: Double, system: Int) -> CGPoint {
        let strip = LyreCards.strip(systems[system])
        return CGPoint(x: (CGFloat(x) - left) * scale,
                       y: stripFrame(system).minY + (strip.maxY - CGFloat(y)) * scale)
    }

    func box(_ place: NotePlace) -> CGRect {
        let hs = CGFloat(systems[place.system].halfSpace)
        let centre = point(x: place.x + Self.headCentre * hs, y: place.y, system: place.system)
        let width = Self.boxWidth * hs * scale, height = Self.boxHeight * hs * scale
        return CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
    }

    /// The line under a point on the card.
    func system(at point: CGPoint) -> Int? {
        card.systems.first { stripFrame($0).minY <= point.y && point.y < stripFrame($0).maxY }
    }

    /// The note a tap lands on: the nearest placed, pitched note on the line
    /// under the finger, if its head is close enough. A rest is not a target,
    /// since there is nothing to hear, and a note the reader could not place
    /// is not one either, because a guessed target is a wrong note sounded.
    func note(at point: CGPoint, among events: [ScoreEvent]) -> ScoreEvent? {
        guard let line = system(at: point) else { return nil }
        let reach = Self.tapReach * CGFloat(systems[line].halfSpace) * scale
        return events
            .compactMap { event -> (event: ScoreEvent, distance: CGFloat)? in
                guard !event.isRest, let place = event.place, place.system == line else { return nil }
                let centre = box(place)
                let distance = hypot(centre.midX - point.x, centre.midY - point.y)
                return distance <= reach ? (event, distance) : nil
            }
            .min { $0.distance < $1.distance }?.event
    }

    /// Each of `measures` that is on this card, as a frame over the whole bar
    /// on its line, for marking suspect bars the way the list does.
    func barFrames(_ measures: Set<Int>) -> [CGRect] {
        card.systems.flatMap { index -> [CGRect] in
            let frame = stripFrame(index)
            return systems[index].bars.filter { measures.contains($0.measure) }.map { bar in
                let x0 = point(x: bar.x0, y: 0, system: index).x, x1 = point(x: bar.x1, y: 0, system: index).x
                return CGRect(x: x0, y: frame.minY, width: x1 - x0, height: frame.height)
            }
        }
    }

    /// The bar under a point on the card.
    func measure(at point: CGPoint) -> Int? {
        guard let line = system(at: point) else { return nil }
        let x = Double(point.x / scale + left)
        return systems[line].bars.first { $0.x0 <= x && x < $0.x1 }?.measure
    }
}
