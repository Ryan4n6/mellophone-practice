import SwiftUI

/// The selected horn, drawn small enough to sit beside its name (#36).
///
/// Four drawings and not one, because the picture is the thing a player
/// checks at a glance: the wrong horn selected should LOOK wrong. Each is
/// drawn by the one feature that tells it from the others at this size:
///
/// - a trumpet is long and slim with a small bell,
/// - a mellophone is a short trumpet behind a bell as tall as the horn,
/// - a French horn is a coil with the bell hanging off it,
/// - a euphonium stands up, with the bell at the top.
///
/// Made of filled parts and no font or image, like the clef, so nothing
/// loads and it looks the same on every phone. Each part is filled on its
/// own: laid into one path, two parts wound opposite ways cut a hole where
/// they cross.
struct BrassGlyph: View {
    enum Kind: CaseIterable {
        case trumpet, mellophone, frenchHorn, euphonium
    }

    let kind: Kind
    var color: Color = Theme.gold

    var body: some View {
        Canvas { context, size in
            for part in Self.parts(for: kind, in: CGRect(origin: .zero, size: size)) {
                context.fill(part, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    /// The drawing's own box, in its own units. The glyph is scaled to fit
    /// the frame it is given without being stretched, so a trumpet comes out
    /// slimmer than a mellophone in the same frame, which is the point.
    static func box(for kind: Kind) -> CGSize {
        switch kind {
        case .trumpet: return CGSize(width: 24, height: 11)
        case .mellophone: return CGSize(width: 24, height: 16)
        case .frenchHorn: return CGSize(width: 19, height: 16.5)
        case .euphonium: return CGSize(width: 14.5, height: 18)
        }
    }

    static func parts(for kind: Kind, in rect: CGRect) -> [Path] {
        let box = box(for: kind)
        let scale = min(rect.width / box.width, rect.height / box.height)
        let fit = CGAffineTransform(translationX: rect.midX - box.width * scale / 2,
                                    y: rect.midY - box.height * scale / 2)
            .scaledBy(x: scale, y: scale)
        return drawing(for: kind).map { $0.applying(fit) }
    }

    // MARK: - The four drawings

    private static func drawing(for kind: Kind) -> [Path] {
        switch kind {
        case .trumpet:
            return [
                tube([(1, 5.5), (17, 5.5)], 1.5),
                block(0, 4.1, 1.5, 6.9),
                bell(throat: ((16, 4.75), (16, 6.25)), rim: ((24, 1.3), (24, 9.7)),
                     pull: ((21.4, 4.9), (21.4, 6.1))),
                tube([(8, 1.6), (8, 9.3)], 1.4),
                tube([(10.4, 1.6), (10.4, 9.3)], 1.4),
                tube([(12.8, 1.6), (12.8, 9.3)], 1.4),
                // The slide under the valves, which is the square outline a
                // trumpet has and the others do not.
                tube([(5.6, 5.5), (5.6, 10.3), (15.4, 10.3), (15.4, 5.5)], 1.1),
            ]
        case .mellophone:
            return [
                tube([(1, 8), (11, 8)], 1.5),
                block(0, 6.6, 1.5, 9.4),
                // The bell is the instrument: it starts half way along and
                // ends as tall as the whole drawing.
                bell(throat: ((9.5, 7.25), (9.5, 8.75)), rim: ((23.4, 0.4), (23.4, 15.6)),
                     pull: ((18.5, 6.6), (18.5, 9.4))),
                tube([(23.5, 0.3), (23.5, 15.7)], 1.0),
                tube([(4.2, 4.4), (4.2, 11.4)], 1.3),
                tube([(6.2, 4.4), (6.2, 11.4)], 1.3),
                tube([(8.2, 4.4), (8.2, 11.4)], 1.3),
                tube([(2.7, 8), (2.7, 12.6), (10.4, 12.6), (10.4, 9)], 1.1),
            ]
        case .frenchHorn:
            return [
                ring(centre: (7.4, 9.2), radius: 5.1, 1.5),
                ring(centre: (7.4, 9.2), radius: 2.5, 1.0),
                // The leadpipe coming off the top of the coil to the mouth.
                tube([(4.4, 5.2), (1.5, 1.7)], 1.0),
                tube([(0.8, 0.9), (1.7, 2.0)], 1.7),
                // And the bell, out of the coil and as wide as the coil is.
                bell(throat: ((10.9, 8.6), (9.3, 11.4)), rim: ((18.6, 5.6), (13.9, 16.2)),
                     pull: ((16.0, 8.4), (12.4, 14.6))),
                tube([(18.6, 5.6), (13.9, 16.2)], 0.9),
            ]
        case .euphonium:
            return [
                // Up the right side to the bell, round the bottom, and back
                // up the left: the big oval body.
                curve(from: (10.9, 7.6), [((10.9, 13.4), nil), ((6.6, 17.1), (10.9, 17.1)), ((2.3, 13.4), (2.3, 17.1)), ((2.3, 8.2), nil)], 2.0),
                // A bell most of the width of the horn, pointing straight up.
                bell(throat: ((9.9, 8.2), (11.9, 8.2)), rim: ((5.4, 0.6), (14.4, 0.6)),
                     pull: ((9.9, 2.6), (11.9, 2.6))),
                tube([(5.4, 0.6), (14.4, 0.6)], 0.9),
                tube([(4.7, 7.0), (4.7, 12.4)], 1.2),
                tube([(6.5, 7.0), (6.5, 12.4)], 1.2),
                tube([(8.3, 7.0), (8.3, 12.4)], 1.2),
                tube([(0.6, 6.6), (2.3, 6.6), (2.3, 8.4)], 1.1),
                block(0, 5.6, 1.0, 7.6),
            ]
        }
    }

    // MARK: - Parts

    private typealias Point = (CGFloat, CGFloat)

    private static func point(_ p: Point) -> CGPoint { CGPoint(x: p.0, y: p.1) }

    /// A length of tubing along straight lines, as a shape to fill.
    private static func tube(_ points: [Point], _ width: CGFloat) -> Path {
        var line = Path()
        line.addLines(points.map(point))
        return line.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// Tubing with bends in it. A `nil` control is a straight run.
    private static func curve(from start: Point, _ steps: [(to: Point, control: Point?)], _ width: CGFloat) -> Path {
        var line = Path()
        line.move(to: point(start))
        for step in steps {
            if let control = step.control {
                line.addQuadCurve(to: point(step.to), control: point(control))
            } else {
                line.addLine(to: point(step.to))
            }
        }
        return line.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private static func ring(centre: Point, radius: CGFloat, _ width: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.0 - radius, y: centre.1 - radius, width: radius * 2, height: radius * 2))
            .strokedPath(StrokeStyle(lineWidth: width))
    }

    private static func block(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), cornerRadius: 0.4)
    }

    /// A bell: the two sides of the tube at `throat` opening out to the two
    /// ends of the `rim`. `pull` is where each side is drawn toward on the
    /// way, and is what makes it flare late like a bell and not open evenly
    /// like a funnel.
    private static func bell(throat: (Point, Point), rim: (Point, Point), pull: (Point, Point)) -> Path {
        var path = Path()
        path.move(to: point(throat.0))
        path.addQuadCurve(to: point(rim.0), control: point(pull.0))
        path.addLine(to: point(rim.1))
        path.addQuadCurve(to: point(throat.1), control: point(pull.1))
        path.closeSubpath()
        return path
    }
}
