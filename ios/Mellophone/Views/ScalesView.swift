import SwiftUI

struct ScalesView: View {
    @EnvironmentObject private var prefs: Preferences
    @StateObject private var player = ScalePlayer()
    @State private var selected: Scale?

    /// The four speeds from the web version, in milliseconds per note.
    private let speeds: [(label: String, ms: Int)] = [
        ("Slow", 800), ("Medium", 500), ("Fast", 300), ("Presto", 180)
    ]

    var body: some View {
        PageScaffold(title: "Scales", subtitle: "Scales and exercises") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scales & Exercises")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)

                ForEach(Scale.all) { scale in
                    scaleRow(scale)
                }
            }
            .card()

            if let selected {
                detail(for: selected)
            }
        }
        .onDisappear { player.stop() }
    }

    private func scaleRow(_ scale: Scale) -> some View {
        let isSelected = selected?.id == scale.id
        return Button {
            player.stop()
            selected = scale
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(scale.displayName(for: prefs.instrument))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.gold : Theme.text)
                Text(scale.noteNames.joined(separator: " "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isSelected ? Theme.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Theme.goldDim : Theme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func detail(for scale: Scale) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(scale.displayName(for: prefs.instrument))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)

            FlowLayout(spacing: 8) {
                ForEach(Array(scale.notes.enumerated()), id: \.offset) { index, note in
                    Text(note.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(player.currentIndex == index ? Color.black : Theme.text)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(player.currentIndex == index ? Theme.gold : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }

            HStack(spacing: 10) {
                Button {
                    player.play(scale, millisecondsPerNote: prefs.scaleSpeed, volume: prefs.volume)
                } label: {
                    label("Play Scale", systemImage: "play.fill", prominent: true)
                }
                .buttonStyle(.plain)
                .disabled(player.isPlaying)
                .opacity(player.isPlaying ? 0.5 : 1)

                Button {
                    player.stop()
                } label: {
                    label("Stop", systemImage: "stop.fill", prominent: false)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SPEED")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textDim)
                HStack(spacing: 8) {
                    ForEach(speeds, id: \.ms) { speed in
                        Button {
                            // Persisted, unlike the web version, where
                            // saveScaleSpeed writes the value and nothing ever
                            // reads it back on load.
                            prefs.scaleSpeed = speed.ms
                        } label: {
                            Text(speed.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(prefs.scaleSpeed == speed.ms ? Color.black : Theme.textDim)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(prefs.scaleSpeed == speed.ms ? Theme.gold : Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    private func label(_ title: String, systemImage: String, prominent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(prominent ? Color.black : Theme.text)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(prominent ? Theme.gold : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
