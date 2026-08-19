import SwiftUI

/// The Trainer tab: a note on the staff, what it is, and how to play it.
struct TrainerView: View {
    @EnvironmentObject private var prefs: Preferences
    @StateObject private var model = TrainerModel()

    var body: some View {
        PageScaffold(title: "Honk It Up!", subtitle: "Mellophone, horn and trumpet") {
            VStack(spacing: 16) {
                StaffView(note: model.note, revealNote: !model.isHidden)

                noteReadout

                ValveView(
                    fingering: Fingering.value(for: model.note, on: prefs.instrument) ?? "none",
                    revealed: !model.isHidden
                )

                buttons

                instrumentPicker

                rangePickers

                volumeSlider
            }
            .card()

            harmonicsCard

            FingeringChartView(selected: model.note, instrument: prefs.instrument) { note in
                model.select(note)
                model.play(duration: 0.8)
            }
        }
        .onAppear { model.bind(prefs) }
    }

    // MARK: - Pieces

    private var noteReadout: some View {
        VStack(spacing: 2) {
            Text(model.isHidden ? " " : model.note.name)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gold)
            Text(model.isHidden ? " " : String(format: "%.2f Hz", model.note.frequency))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Theme.textDim)
        }
        // A fixed height keeps Hide from collapsing the layout and shifting
        // everything below it, which would make the button feel like it did
        // something other than hide a name.
        .frame(height: 62)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            actionButton("Play", systemImage: "speaker.wave.2.fill", prominent: true) {
                model.play()
            }
            actionButton("Random", systemImage: "die.face.5.fill", prominent: true) {
                model.random()
            }
            actionButton(model.isHidden ? "Show" : "Hide", systemImage: "eye.fill", prominent: false) {
                model.isHidden.toggle()
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.black : Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(prominent ? Theme.gold : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var instrumentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INSTRUMENT")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.textDim)

            Picker("Instrument", selection: $prefs.instrument) {
                ForEach(Instrument.allCases) { instrument in
                    Text(instrument.shortName).tag(instrument)
                }
            }
            .pickerStyle(.segmented)

            // Said out loud rather than left to be discovered. A horn player
            // trusting a mellophone chart would learn wrong fingerings, which is
            // the same failure mode as the wrong data in #9.
            if let caveat = prefs.instrument.caveat {
                Text(caveat)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangePickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRACTICE RANGE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.textDim)

            HStack {
                Text("Low").font(.system(size: 14)).foregroundStyle(Theme.text)
                Spacer()
                Picker("Low", selection: $prefs.rangeLow) {
                    ForEach(Note.selectable) { Text($0.name).tag($0.name) }
                }
                .tint(Theme.gold)
            }
            HStack {
                Text("High").font(.system(size: 14)).foregroundStyle(Theme.text)
                Spacer()
                Picker("High", selection: $prefs.rangeHigh) {
                    ForEach(Note.selectable) { Text($0.name).tag($0.name) }
                }
                .tint(Theme.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var volumeSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").foregroundStyle(Theme.textDim)
            Slider(value: $prefs.volume, in: 0.01...1)
                .tint(Theme.gold)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.textDim)
        }
    }

    /// Notes sharing the current note's fingering ON THE CURRENT INSTRUMENT.
    /// The grouping itself lives in `Instrument.swift` next to the derivation it
    /// depends on, and InstrumentTests covers it (#13).
    private var sameFingering: [Note] {
        model.note.sameFingering(on: prefs.instrument)
    }

    private var harmonicsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Same Fingering (Harmonic Series)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)

            if model.isHidden {
                Text("Hidden")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
            } else if sameFingering.isEmpty {
                Text("No other notes share this fingering")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
            } else {
                // The point of this card: these are the notes the valves will
                // not separate for you, so your ear and your embouchure have to.
                FlowLayout(spacing: 8) {
                    ForEach(sameFingering) { note in
                        Button {
                            model.select(note)
                            model.play(duration: 1.0)
                        } label: {
                            Text(note.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Theme.surface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }
}

/// Holds the trainer's state and its tone player.
///
/// Separate from the view so the player survives SwiftUI rebuilding the body,
/// which happens on every slider drag.
final class TrainerModel: ObservableObject {
    @Published private(set) var note: Note = Note.named("C5") ?? Note.all[0]
    @Published var isHidden = false

    private let tone = TonePlayer()
    private weak var prefs: Preferences?

    func bind(_ prefs: Preferences) {
        self.prefs = prefs
        #if DEBUG
        // Lets a screenshot of any note be taken without tapping the phone:
        //
        //     xcrun simctl launch booted com.massfeller.mellophone -startNote F3
        //
        // Arguments of the form -key value land in UserDefaults, so this needs
        // no argument parsing. It exists because the notes worth LOOKING at are
        // the ends of the range, where the ledger lines are, and those are
        // precisely the ones that are tedious to reach by hand.
        if let name = UserDefaults.standard.string(forKey: "startNote"),
           let requested = Note.named(name) {
            note = requested
        }
        #endif
    }

    func select(_ note: Note) {
        self.note = note
    }

    func play(duration: Double = 1.2) {
        tone.volume = prefs?.volume ?? 0.25
        tone.play(note, duration: duration)
    }

    /// A different note from somewhere in the practice range.
    func random() {
        let range = prefs?.range ?? Note.selectable
        guard range.count > 1 else { return }
        var next = note
        // Never hand back the same note twice: "Random" that repeats reads as
        // a broken button rather than as chance.
        while next.name == note.name {
            next = range.randomElement() ?? note
        }
        note = next
        play()
    }
}

/// Wrapping row layout for the harmonic chips. SwiftUI has no built-in flow
/// layout and an HStack would run off the edge once a fingering has five
/// partials on it.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
