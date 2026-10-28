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
    /// Read here and not passed in, so a change of note names redraws the
    /// chart (#67).
    @EnvironmentObject private var prefs: Preferences

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Fingering Chart")
                    .scaledFont(15, .bold)
                    .foregroundStyle(Theme.text)
                Text(instrument.displayName)
                    .scaledFont(12)
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
                Text(prefs.noteNaming.show(note.name))
                    .scaledFont(13, .bold)
                    .foregroundStyle(isSelected ? Color.black : Theme.text)
                Spacer(minLength: 0)
                Text(Fingering.value(for: note, on: instrument).map(Fingering.shown) ?? "?")
                    .scaledFont(12, .semibold)
                    .foregroundStyle(isSelected ? Color.black.opacity(0.7) : Theme.textDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6).frame(minHeight: 38)
            .background(isSelected ? Theme.gold : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(prefs.noteNaming.show(note.name)), \(Fingering.value(for: note, on: instrument).map(Fingering.shown) ?? String(localized: "no fingering"))")
    }
}
