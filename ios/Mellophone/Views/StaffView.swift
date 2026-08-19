import SwiftUI

/// A single note on a treble staff.
///
/// Coordinates match the web version's SVG space so the two products stay
/// comparable: five staff lines at y = 60, 80, 100, 120, 140, which in treble
/// clef are F5, D5, B4, G4, E4. The space is 230 tall rather than the web's 200
/// because the bottom of the mellophone's range needs a third ledger line below
/// the staff, which the web version never had room for.
///
/// The conversion from `staffPosition` is NOT the one in `index.html`. See
/// `StaffGeometry.y(for:)`.
struct StaffView: View {
    let note: Note
    /// Hides the accidental and note head without collapsing the layout, for
    /// the Trainer's Hide mode.
    var revealNote: Bool = true

    var body: some View {
        Canvas { context, size in
            let scale = size.width / StaffGeometry.width
            context.scaleBy(x: scale, y: scale)
            draw(in: &context)
        }
        .aspectRatio(StaffGeometry.width / StaffGeometry.height, contentMode: .fit)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(revealNote ? "\(note.name) on the staff" : "A hidden note on the staff")
    }

    private func draw(in context: inout GraphicsContext) {
        let ink = Color.black
        let y = StaffGeometry.y(for: note)

        // Staff.
        var staff = Path()
        for lineY in StaffGeometry.staffLineYs {
            staff.move(to: CGPoint(x: StaffGeometry.staffLeft, y: lineY))
            staff.addLine(to: CGPoint(x: StaffGeometry.staffRight, y: lineY))
        }
        context.stroke(staff, with: .color(ink), lineWidth: 1.5)

        // Ledger lines. Above and below need SEPARATE tests: a line above the
        // staff is needed when the note reaches up to it, one below when the
        // note reaches down to it. Sharing a single test is what leaves the
        // lower ledgers permanently drawn in the web version (issue #8).
        var ledgers = Path()
        for lineY in StaffGeometry.ledgerYsAbove where y <= lineY + 5 {
            ledgers.move(to: CGPoint(x: StaffGeometry.ledgerLeft, y: lineY))
            ledgers.addLine(to: CGPoint(x: StaffGeometry.ledgerRight, y: lineY))
        }
        for lineY in StaffGeometry.ledgerYsBelow where y >= lineY - 5 {
            ledgers.move(to: CGPoint(x: StaffGeometry.ledgerLeft, y: lineY))
            ledgers.addLine(to: CGPoint(x: StaffGeometry.ledgerRight, y: lineY))
        }
        context.stroke(ledgers, with: .color(ink), lineWidth: 1.5)

        // Treble clef, drawn as a path rather than set as U+1D11E. No font
        // shipped with iOS covers that codepoint: of the 264 font files in the
        // iOS 26.5 runtime, zero have a glyph for it, so setting it as text
        // renders an empty box on a phone. Checked, not assumed.
        //
        // FILLED, not stroked. It used to be a hand-drawn centreline stroked
        // with a round cap, which reads as a squiggle rather than as engraving:
        // real clefs have weight that swells and tapers, and a constant-width
        // stroke cannot. Now both products draw the same artwork, generated
        // into TrebleClef.swift by ios/scripts/make-treble-clef.py.
        context.fill(TrebleClef.path, with: .color(ink))

        guard revealNote else { return }

        // Accidental, to the left of the head, drawn as a path for the same
        // reason the clef is.
        //
        // These two ARE in the Basic Multilingual Plane and iOS does have faces
        // covering them, but not the same set: 25 fonts carry U+266F and only 13
        // carry U+266D. Times New Roman is a concrete example of a serif face
        // that has the sharp and lacks the flat. Asking for a serif glyph and
        // letting CoreText fall back therefore risks rendering the sharp and the
        // flat in two DIFFERENT typefaces on the same staff, at sizes and weights
        // that were never meant to sit together. Paths make them consistent and
        // remove the last font dependency from the staff.
        if let accidental = StaffGeometry.accidentalPath(note.accidental, at: y) {
            context.stroke(
                accidental,
                with: .color(ink),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            )
        }

        // Note head: an ellipse tilted the way an engraved head is.
        let head = Path(ellipseIn: CGRect(
            x: StaffGeometry.headX - StaffGeometry.headRadiusX,
            y: y - StaffGeometry.headRadiusY,
            width: StaffGeometry.headRadiusX * 2,
            height: StaffGeometry.headRadiusY * 2
        ))
        context.drawLayer { layer in
            layer.translateBy(x: StaffGeometry.headX, y: y)
            layer.rotate(by: .degrees(-20))
            layer.translateBy(x: -StaffGeometry.headX, y: -y)
            layer.fill(head, with: .color(ink))
        }

        // Stem. Notes above the middle line hang their stem down on the left;
        // everything from the middle line down puts it up on the right.
        var stem = Path()
        if y <= StaffGeometry.middleLineY {
            stem.move(to: CGPoint(x: StaffGeometry.headX - StaffGeometry.headRadiusX + 1, y: y))
            stem.addLine(to: CGPoint(x: StaffGeometry.headX - StaffGeometry.headRadiusX + 1, y: y + StaffGeometry.stemLength))
        } else {
            stem.move(to: CGPoint(x: StaffGeometry.headX + StaffGeometry.headRadiusX - 1, y: y))
            stem.addLine(to: CGPoint(x: StaffGeometry.headX + StaffGeometry.headRadiusX - 1, y: y - StaffGeometry.stemLength))
        }
        context.stroke(stem, with: .color(ink), lineWidth: 2.5)
    }
}

/// The staff's coordinate system, kept in one place so the drawing code and any
/// test agree on it.
enum StaffGeometry {
    static let width: CGFloat = 420
    static let height: CGFloat = 230

    static let staffLineYs: [CGFloat] = [60, 80, 100, 120, 140]
    static let middleLineY: CGFloat = 100          // B4
    static let staffLeft: CGFloat = 30
    static let staffRight: CGFloat = 390

    /// A5 and C6.
    static let ledgerYsAbove: [CGFloat] = [40, 20]
    /// C4, A3 and F3. The web version has only the first two; the mellophone's
    /// written range goes down to F3, which needs the third.
    static let ledgerYsBelow: [CGFloat] = [160, 180, 200]
    static let ledgerLeft: CGFloat = 218
    static let ledgerRight: CGFloat = 282

    static let headX: CGFloat = 250
    static let headRadiusX: CGFloat = 12
    static let headRadiusY: CGFloat = 9
    static let stemLength: CGFloat = 70            // 3.5 staff spaces
    static let accidentalX: CGFloat = 218

    /// Convert a note's staff coordinate to a drawing y.
    ///
    /// `staffPosition` counts diatonic steps in units of 10, C6 = 0 down to
    /// F3 = 180. One diatonic step is half a staff space, a staff space is 20
    /// units, so a step is 10 units and the conversion is a straight offset.
    ///
    /// `index.html` uses `staffPos * 0.5 + 30`, which halves the scale and puts
    /// every note at the wrong height: not one line note lands on its line, and
    /// the whole F3 to C6 range collapses into the top half of the staff. That
    /// is issue #8. This is the one place the native app is deliberately NOT
    /// faithful to the spec, because the spec is wrong here, and a note-reading
    /// drill that draws the wrong note teaches the wrong thing.
    static func y(for note: Note) -> CGFloat {
        CGFloat(note.staffPosition) + 20
    }

    /// A sharp or a flat, positioned against the note's y. Returns nil for a
    /// natural, which is never drawn here.
    ///
    /// Both are stroked outlines rather than filled glyph shapes, which keeps
    /// them in the same visual language as the clef.
    static func accidentalPath(_ accidental: Accidental, at y: CGFloat) -> Path? {
        var p = Path()
        let x = accidentalX
        switch accidental {
        case .natural:
            return nil

        case .sharp:
            // Two verticals and two slightly rising horizontals. The horizontals
            // rise so they cannot disappear into a staff line they run parallel
            // to, which is why engraved sharps are drawn that way.
            for dx in [CGFloat(-4), 4] {
                p.move(to: CGPoint(x: x + dx, y: y - 15))
                p.addLine(to: CGPoint(x: x + dx, y: y + 13))
            }
            for dy in [CGFloat(-5), 5] {
                p.move(to: CGPoint(x: x - 9, y: y + dy + 2.5))
                p.addLine(to: CGPoint(x: x + 9, y: y + dy - 2.5))
            }

        case .flat:
            // A stem with a loop hung off its lower half. The loop's belly sits
            // ON the note's line, which is what makes a flat read as belonging
            // to that note rather than the one below it.
            // The stem runs about two staff spaces above the belly, which is
            // what an engraved flat does. A short stem reads as a stray mark
            // next to the note rather than as an accidental attached to it.
            p.move(to: CGPoint(x: x - 5, y: y - 32))
            p.addLine(to: CGPoint(x: x - 5, y: y + 10))
            p.move(to: CGPoint(x: x - 5, y: y + 10))
            p.addCurve(
                to: CGPoint(x: x - 5, y: y - 5),
                control1: CGPoint(x: x + 11, y: y + 7),
                control2: CGPoint(x: x + 10, y: y - 6)
            )
        }
        return p
    }

}
