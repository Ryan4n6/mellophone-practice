import SwiftUI

/// The whole chart, always one scroll away.
///
/// The web version keeps this permanently visible below every panel. iOS
/// collapses a sixth tab into a "More" list, which is worse than a scroll, so it
/// lives at the bottom of the Trainer instead.
struct FingeringChartView: View {
    let selected: Note
    let instrument: Instrument
    let onSelect: (Note) -> Void

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Fingering Chart")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(instrument.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                // `selectable`, not the full table: a person picking from a list
                // should not be offered both spellings of the same pitch.
                ForEach(Note.selectable) { note in
                    row(note)
                }
            }
        }
        .card()
    }

    private func row(_ note: Note) -> some View {
        let isSelected = note.name == selected.name
        return Button {
            onSelect(note)
        } label: {
            HStack(spacing: 6) {
                Text(note.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? Color.black : Theme.text)
                Spacer(minLength: 0)
                Text(Fingering.value(for: note, on: instrument) ?? "?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.7) : Theme.textDim)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(isSelected ? Theme.gold : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(note.name), \(Fingering.value(for: note, on: instrument) ?? "no fingering")")
    }
}
