import SwiftUI

/// The Trainer tab: a note on the staff, what it is, and how to play it.
struct TrainerView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var metronome: Metronome
    @StateObject private var model = TrainerModel()
    /// The notes the tuner is open on. Nil when it is closed.
    @State private var tuning: Tuning?

    /// What the tuner sheet is shown for: the notes for the horn that was
    /// selected on the way in. The sheet works them out again itself if the
    /// horn is changed while it is open (#36).
    private struct Tuning: Identifiable {
        let id = UUID()
        let targets: [NoteCheckTarget]
        var first = 0
    }

    var body: some View {
        PageScaffold(title: "Honk It Up!", subtitle: "Mellophone, horn, trumpet and euphonium") {
            VStack(spacing: 16) {
                StaffView(note: model.note, revealNote: !model.isHidden)

                noteReadout

                ValveView(
                    fingering: Fingering.value(for: model.note, on: prefs.instrument) ?? "none",
                    revealed: !model.isHidden
                )

                buttons

                instrumentPicker

                tuneButton

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
        .onAppear {
            model.bind(prefs)
            #if DEBUG
            // Opens the tuner without a finger, for a screenshot:
            //   xcrun simctl launch booted com.massfeller.mellophone \
            //     -tune YES -listenFake 352
            // -tuneNote 2 opens it on the second tuning note. Once per
            // launch, or closing the sheet would open it again.
            if !Self.didAutoTune, UserDefaults.standard.bool(forKey: "tune") {
                Self.didAutoTune = true
                tune(startingAt: max(0, UserDefaults.standard.integer(forKey: "tuneNote") - 1))
            }
            #endif
        }
        .sheet(item: $tuning) { tuning in
            NoteCheckView(targets: tuning.targets, tone: model.referenceTone, startingAt: tuning.first,
                          retarget: NoteCheckTarget.tuning(for:))
                .environmentObject(prefs)
                .preferredColorScheme(.dark)
        }
    }

    #if DEBUG
    private static var didAutoTune = false
    #endif

    /// Open the tuner for the selected horn.
    ///
    /// Everything that makes a sound is stopped first, the metronome
    /// included, for the same reason a chart does it before the note check:
    /// that screen turns the microphone on, and a click in the room is a
    /// pitch as far as a microphone is concerned.
    private func tune(startingAt first: Int = 0) {
        let targets = NoteCheckTarget.tuning(for: prefs.instrument)
        guard !targets.isEmpty else {
            Log.audio.error("[TUNE] no tuning note for \(prefs.instrument.rawValue, privacy: .public), not opening the tuner")
            return
        }
        model.stop()
        if metronome.isRunning {
            Log.audio.info("[TUNE] stopping the metronome for the tuner")
            metronome.stop(reason: "tuner")
        }
        let names = targets.map { "\($0.choice ?? "?") = written \($0.check.writtenName)" }.joined(separator: ", ")
        Log.audio.info("[TUNE] opening for \(prefs.instrument.rawValue, privacy: .public): \(names, privacy: .public)")
        #if DEBUG
        FileLog.write("[TUNE] opening for \(prefs.instrument.rawValue): \(names)")
        #endif
        tuning = Tuning(targets: targets, first: first)
    }

    // MARK: - Pieces

    private var noteReadout: some View {
        VStack(spacing: 2) {
            Text(model.isHidden ? " " : prefs.noteNaming.show(model.note.name))
                .scaledFont(42, .bold, design: .rounded)
                .foregroundStyle(Theme.gold)
            // In the reader's own number format: 523,25 Hz in French (#67).
            Text(model.isHidden ? " " : "\(model.note.frequency.formatted(.number.precision(.fractionLength(2)))) Hz")
                .scaledFont(13)
                .monospacedDigit()
                .foregroundStyle(Theme.textDim)
        }
        // A floor keeps Hide from collapsing the layout and shifting
        // everything below it, which would make the button feel like it did
        // something other than hide a name. A floor and not a fixed height,
        // because at a large text size the name outgrows 62 points and ran
        // into the valves (#66).
        .frame(minHeight: 62)
    }

    private var buttons: some View { buttonsRow.controlTextCap() }

    private var buttonsRow: some View {
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

    private func actionButton(_ title: LocalizedStringResource, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).scaledFont(15, .semibold)
                Text(title).scaledFont(12, .semibold)
            }
            .foregroundStyle(prominent ? Color.black : Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6).frame(minHeight: 56)
            .background(prominent ? Theme.gold : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var instrumentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INSTRUMENT")
                .scaledFont(12, .semibold)
                .tracking(0.5)
                .foregroundStyle(Theme.textDim)

            Picker("Instrument", selection: $prefs.instrument) {
                ForEach(Instrument.allCases) { instrument in
                    Text(instrument.shortName).tag(instrument)
                }
            }
            .pickerStyle(.segmented)
            .controlTextCap()

            // Said out loud rather than left to be discovered. A horn player
            // trusting a mellophone chart would learn wrong fingerings, which is
            // the same failure mode as the wrong data in #9.
            if let caveat = prefs.instrument.caveat {
                Text(caveat)
                    .scaledFont(12)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The way into the tuner (#32). Under the instrument picker because the
    /// note a horn tunes to depends on which horn it is, and because all five
    /// tabs are taken.
    private var tuneButton: some View {
        Button { tune() } label: {
            HStack(spacing: 10) {
                Image(systemName: "tuningfork")
                    .scaledFont(16, .semibold)
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tune your horn")
                        .scaledFont(15, .semibold)
                        .foregroundStyle(Theme.text)
                    Text("Play your tuning note and see if you are flat or sharp")
                        .scaledFont(12)
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .scaledFont(12, .semibold)
                    .foregroundStyle(Theme.textDim)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Turns the microphone on while the tuner is open")
    }

    private var rangePickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRACTICE RANGE")
                .scaledFont(12, .semibold)
                .tracking(0.5)
                .foregroundStyle(Theme.textDim)

            HStack {
                Text("Low").scaledFont(14).foregroundStyle(Theme.text)
                Spacer()
                Picker("Low", selection: $prefs.rangeLow) {
                    ForEach(Note.selectable) { Text(prefs.noteNaming.show($0.name)).tag($0.name) }
                }
                .tint(Theme.gold)
            }
            HStack {
                Text("High").scaledFont(14).foregroundStyle(Theme.text)
                Spacer()
                Picker("High", selection: $prefs.rangeHigh) {
                    ForEach(Note.selectable) { Text(prefs.noteNaming.show($0.name)).tag($0.name) }
                }
                .tint(Theme.gold)
            }
            // How every note in the app is named (#67). Here, with the range,
            // because the range is the other thing a student sets once for
            // how they read. It defaults to the phone's language.
            HStack {
                Text("Note names").scaledFont(14).foregroundStyle(Theme.text)
                Spacer()
                Picker("Note names", selection: $prefs.noteNaming) {
                    ForEach(NoteNaming.allCases) { Text($0.label).tag($0) }
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
                .scaledFont(15, .bold)
                .foregroundStyle(Theme.text)

            if model.isHidden {
                Text("Hidden")
                    .scaledFont(13)
                    .foregroundStyle(Theme.textDim)
            } else if sameFingering.isEmpty {
                Text("No other notes share this fingering")
                    .scaledFont(13)
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
                            Text(prefs.noteNaming.show(note.name))
                                .scaledFont(13, .semibold)
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6).frame(minHeight: 34)
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

    func stop() {
        tone.stop()
    }

    /// The Trainer's own player, lent to the tuner for "Hear it". See
    /// `ReferenceTone` for why the tuner does not get one of its own.
    var referenceTone: ReferenceTone { tone }

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
