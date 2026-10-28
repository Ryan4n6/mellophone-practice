import SwiftUI

/// The three valve buttons, lit for whichever are down.
///
/// Reads the fingering DISPLAY STRING rather than a parsed structure, exactly as
/// the web version's `updateValves` does, so the chart and the diagram cannot
/// disagree about what a note takes.
struct ValveView: View {
    let fingering: String
    var revealed: Bool = true
    /// The Trainer's size by default. The part screen keeps this pinned beside
    /// a staff while a list scrolls under it and has room for about half that.
    var diameter: CGFloat = 52

    var body: some View {
        VStack(spacing: diameter * 0.19) {
            HStack(spacing: diameter * 0.31) {
                ForEach(1...3, id: \.self) { valve in
                    valveCircle(valve)
                }
            }
            Text(revealed ? shown : " ")
                .font(.system(size: max(13, diameter * 0.33), weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(revealed ? "Fingering \(shown)" : "Fingering hidden")
    }

    /// What is printed under the valves: "Open" in the reader's language
    /// (#67), and a word, not "none", for a note no fingering reaches.
    private var shown: String {
        fingering == "none" ? String(localized: "No fingering") : Fingering.shown(fingering)
    }

    private func valveCircle(_ valve: Int) -> some View {
        let down = revealed && fingering.contains(String(valve))
        return Text("\(valve)")
            .font(.system(size: max(11, diameter * 0.33), weight: .bold, design: .rounded))
            .foregroundStyle(down ? Color.black : Theme.textDim)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(down ? Theme.gold : Theme.surface)
            )
            .overlay(
                Circle().stroke(down ? Theme.gold : Theme.cardBorder, lineWidth: 2)
            )
            .animation(.easeOut(duration: 0.12), value: down)
    }
}
