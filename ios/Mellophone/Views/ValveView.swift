import SwiftUI

/// The three valve buttons, lit for whichever are down.
///
/// Reads the fingering DISPLAY STRING rather than a parsed structure, exactly as
/// the web version's `updateValves` does, so the chart and the diagram cannot
/// disagree about what a note takes.
struct ValveView: View {
    let fingering: String
    var revealed: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                ForEach(1...3, id: \.self) { valve in
                    valveCircle(valve)
                }
            }
            Text(revealed ? fingering : " ")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(revealed ? "Fingering \(fingering)" : "Fingering hidden")
    }

    private func valveCircle(_ valve: Int) -> some View {
        let down = revealed && fingering.contains(String(valve))
        return Text("\(valve)")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(down ? Color.black : Theme.textDim)
            .frame(width: 52, height: 52)
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
