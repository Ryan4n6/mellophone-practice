import SwiftUI

struct MetronomeView: View {
    @EnvironmentObject private var metronome: Metronome

    /// Time-signature choices from the web version. 6/8 is counted as six clicks
    /// here, exactly as `setTimeSig(6)` does there.
    private let timeSignatures: [(label: String, beats: Int)] = [
        ("2/4", 2), ("3/4", 3), ("4/4", 4), ("6/8", 6)
    ]

    private let presets: [(label: String, bpm: Int)] = [
        ("Largo", 60), ("Andante", 80), ("Allegro", 120), ("Vivace", 160)
    ]

    var body: some View {
        PageScaffold(title: "Metronome", subtitle: "Locked to the audio clock") {
            VStack(spacing: 18) {
                tempoReadout
                tempoControls
                beatDots
                transportButton
                section("Time Signature") { timeSignatureRow }
                section("Presets") { presetRow }
                hapticToggle
            }
            .card()

            #if DEBUG
            DriftReadout()
            #endif
        }
    }

    // MARK: - Pieces

    private var tempoReadout: some View {
        VStack(spacing: 0) {
            Text("\(metronome.tempo)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.gold)
                // A fixed-width digit style plus a fixed frame stops the whole
                // layout jumping as the number goes 99 -> 100 while dragging.
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.12), value: metronome.tempo)
            Text("BPM")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .tracking(1)
        }
    }

    private var tempoControls: some View {
        HStack(spacing: 12) {
            stepButton("minus", delta: -5)
            Slider(
                value: Binding(
                    get: { Double(metronome.tempo) },
                    set: { metronome.tempo = Int($0.rounded()) }
                ),
                in: 40...220,
                step: 1
            )
            .tint(Theme.gold)
            stepButton("plus", delta: 5)
        }
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            metronome.nudgeTempo(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        // 44x44 is Apple's minimum tap target, and this one gets hit with the
        // side of a thumb while the other hand is holding a horn.
        .accessibilityLabel(delta > 0 ? "Increase tempo 5 BPM" : "Decrease tempo 5 BPM")
    }

    private var beatDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<metronome.beatsPerMeasure, id: \.self) { index in
                Circle()
                    .fill(fill(for: index))
                    .frame(width: index == 0 ? 16 : 12, height: index == 0 ? 16 : 12)
                    .animation(.easeOut(duration: 0.08), value: metronome.currentBeat)
            }
        }
        .frame(height: 20)
    }

    private func fill(for index: Int) -> Color {
        guard metronome.currentBeat == index else {
            return index == 0 ? Theme.goldDim.opacity(0.45) : Theme.cardBorder
        }
        return index == 0 ? Theme.gold : Theme.text
    }

    private var transportButton: some View {
        Button {
            metronome.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: metronome.isRunning ? "pause.fill" : "play.fill")
                Text(metronome.isRunning ? "Stop" : "Start")
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(metronome.isRunning ? Theme.text : Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(metronome.isRunning ? Theme.surface : Theme.gold)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var timeSignatureRow: some View {
        HStack(spacing: 8) {
            ForEach(timeSignatures, id: \.beats) { item in
                chip(item.label, selected: metronome.beatsPerMeasure == item.beats) {
                    metronome.beatsPerMeasure = item.beats
                }
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.bpm) { item in
                chip(item.label, selected: metronome.tempo == item.bpm) {
                    metronome.applyPreset(item.bpm)
                }
            }
        }
    }

    private var hapticToggle: some View {
        Toggle(isOn: $metronome.hapticsEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Downbeat haptic")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Feel beat one through the case")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .tint(Theme.gold)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Theme.textDim)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selected ? Theme.gold : Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.textDim)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
/// Debug-only readout of what the click is actually doing. This exists so the
/// timing claim in issue #3 can be answered with measurements taken on the
/// device rather than with an assertion about the design.
struct DriftReadout: View {
    @EnvironmentObject private var metronome: Metronome
    @State private var report: Metronome.DriftReport?

    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TIMING (DEBUG)")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.textDim)

            if let report {
                row("Beats", "\(report.beatsSounded)")
                row("Audio clock", String(format: "%.3f s", report.audioElapsed))
                row("Wall clock", String(format: "%.3f s", report.wallElapsed))
                row("Skew", String(format: "%+.1f ms", report.wallClockSkew * 1000))
                row("Max schedule error", String(format: "%.3f samples", report.maxScheduleErrorSamples))
            } else {
                Text("Start the metronome to measure.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .card()
        .onReceive(refresh) { _ in report = metronome.driftReport() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textDim)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
    }
}
#endif
