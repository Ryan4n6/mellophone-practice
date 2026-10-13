import SwiftUI

/// Which horn the app is set to, on every screen, and the way to change it
/// from wherever you are (#36).
///
/// Every fingering, every concert key and every pitch the microphone is held
/// up to is worked out for one instrument, and until this existed the only
/// place that said which was a picker half way down the Trainer tab. A
/// student on the tuner with the wrong horn selected is told they are a
/// fourth out and has no way to see why. The first time the tuner was used,
/// the phone's log shows it being closed to go and change the instrument.
///
/// It shows the NAME, with one brass glyph beside it, and not a picture per
/// instrument. A mellophone, a trumpet, a horn and a euphonium drawn at 18
/// points are four smudges, and the name is the word a director says.
struct InstrumentChip: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Menu {
            Picker("Instrument", selection: $prefs.instrument) {
                ForEach(Instrument.allCases) { instrument in
                    Text(instrument.displayName).tag(instrument)
                }
            }
        } label: {
            HStack(spacing: 6) {
                BrassGlyph()
                    .fill(Theme.gold)
                    .frame(width: 20, height: 13)
                Text(prefs.instrument.shortName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.goldDim.opacity(0.6), lineWidth: 1))
            // The capsule is 30 tall because it shares a row with titles. The
            // finger gets the 44 a button is owed.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Instrument: \(prefs.instrument.displayName)")
        .accessibilityHint("Changes the instrument the fingerings and pitches are worked out for")
    }
}

/// A valved brass instrument from the side, small enough to sit beside a word:
/// mouthpiece on the left, three valves, the bell on the right.
///
/// One filled outline and no strokes, so it stays legible at 13 points tall
/// where a stroked drawing turns to hairlines.
struct BrassGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func x(_ value: CGFloat) -> CGFloat { rect.minX + rect.width * value }
        func y(_ value: CGFloat) -> CGFloat { rect.minY + rect.height * value }
        func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: x(x0), y: y(y0), width: rect.width * (x1 - x0), height: rect.height * (y1 - y0))
        }
        var path = Path()
        // The mouthpiece, then the leadpipe running into the bell.
        path.addRect(box(0.00, 0.34, 0.06, 0.62))
        path.addRect(box(0.04, 0.41, 0.70, 0.55))
        // The bell: the pipe opening out to the full height at the right.
        path.move(to: CGPoint(x: x(0.66), y: y(0.41)))
        path.addQuadCurve(to: CGPoint(x: x(1.00), y: y(0.02)), control: CGPoint(x: x(0.88), y: y(0.40)))
        path.addLine(to: CGPoint(x: x(1.00), y: y(0.94)))
        path.addQuadCurve(to: CGPoint(x: x(0.66), y: y(0.55)), control: CGPoint(x: x(0.88), y: y(0.56)))
        path.closeSubpath()
        // Three valves standing through the pipe, and the slide under them.
        for left in [0.26, 0.38, 0.50] as [CGFloat] {
            path.addRect(box(left, 0.10, left + 0.07, 0.84))
        }
        path.addRect(box(0.20, 0.84, 0.63, 0.98))
        path.addRect(box(0.20, 0.55, 0.25, 0.98))
        return path
    }
}
