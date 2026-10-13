import SwiftUI
import UIKit

/// The note a student held their finger on, and everything the check screen
/// needs to show it.
struct NoteCheckTarget: Identifiable {
    let id: UUID
    let check: NoteCheck
    /// The table row to draw on the staff. Nil for a pitch outside the chart,
    /// which has a name and a sound and no place this staff can put it.
    let drawn: Note?
    let fingering: String?
    /// What to call this one where there are several to pick from: the
    /// tuner's "Concert F". Nil for a note out of a chart, which is alone.
    var choice: String?
}

extension NoteCheckTarget {
    /// The notes `instrument` tunes to, ready for the check screen (#32).
    ///
    /// A row whose written note is not in the table is left out and logged.
    /// That cannot happen with the table as it stands, and a test says so,
    /// but a tuner with one note is better than a screen that will not open.
    static func tuning(for instrument: Instrument) -> [NoteCheckTarget] {
        instrument.tuningNotes.compactMap { tuning in
            guard let note = Note.named(tuning.writtenName) else {
                Log.audio.error("[TUNE] \(tuning.writtenName, privacy: .public) is not a note this app knows, left out for \(instrument.rawValue, privacy: .public)")
                return nil
            }
            return NoteCheckTarget(
                id: UUID(),
                check: NoteCheck(writtenName: note.name, writtenFrequency: note.frequency,
                                 instrument: instrument, purpose: .tuning),
                drawn: note,
                fingering: Fingering.value(for: note, on: instrument),
                choice: "Concert \(tuning.concert)")
        }
    }
}

/// One note: see it, finger it, hear it, play it, and be told whether what
/// came out of the horn was it.
///
/// Reached by holding a note in a chart. It is a screen of its own and not a
/// mode of the chart, because of the microphone: listening is on while this is
/// open and off when it closes, and that has to be as plain to the person
/// holding the phone as a door.
///
/// The tuner (#32) is this screen too, opened from the Trainer on the notes a
/// horn tunes to. One screen and two doors, on purpose: the app's promise is
/// that the microphone is on in exactly one place, and a second screen with
/// its own listener would have made that two.
struct NoteCheckView: View {
    /// One note out of a chart, or the notes a horn tunes to. Never empty.
    let targets: [NoteCheckTarget]
    /// Borrowed from whoever opened this. See `ReferenceTone`.
    let tone: ReferenceTone

    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var listener = PitchListener()
    @State private var confirmation = NoteConfirmation()
    @State private var chosen: Int

    init(target: NoteCheckTarget, tone: ReferenceTone) {
        self.init(targets: [target], tone: tone)
    }

    init(targets: [NoteCheckTarget], tone: ReferenceTone, startingAt first: Int = 0) {
        self.targets = targets
        self.tone = tone
        _chosen = State(initialValue: min(max(first, 0), max(targets.count - 1, 0)))
    }

    private var target: NoteCheckTarget { targets[min(chosen, targets.count - 1)] }
    private var check: NoteCheck { target.check }
    private var isTuning: Bool { check.purpose == .tuning }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        if targets.count > 1 { choices }
                        note
                        hearing
                        reference
                        if isTuning {
                            // Said here because it is the commonest reason a
                            // horn that was in tune yesterday is not today,
                            // and no needle can tell the two apart.
                            Text("Warm the horn up before you tune. A cold horn plays flat, and you will push the slide in for nothing.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textDim)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                        }
                        Text("The microphone is on only while this screen is open. Nothing is recorded, saved or sent anywhere.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textDim)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear { listener.start(target: check.soundingFrequency) }
        .onDisappear {
            listener.stop()
            tone.stop()
        }
        // A different tuning note is a different target for everything: the
        // needle, the picture, and whether the last note counted.
        .onChange(of: chosen) { _, _ in
            tone.stop()
            listener.targetFrequency = check.soundingFrequency
            confirmation = NoteConfirmation()
            Log.audio.info("[TUNE] now on \(target.choice ?? "?", privacy: .public): written \(check.writtenName, privacy: .public), \(check.soundingFrequency, privacy: .public) Hz")
            #if DEBUG
            FileLog.write("[TUNE] now on \(target.choice ?? "?"): written \(check.writtenName), \(check.soundingFrequency) Hz")
            #endif
        }
        // Only the BACKGROUND stops it. The permission question and Control
        // Center both make the app inactive without leaving it, and stopping
        // for those would turn the microphone off in answer to the student
        // saying yes to it.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                listener.stop()
            } else if phase == .active, listener.state == .idle {
                listener.start(target: check.soundingFrequency)
            }
        }
        .onChange(of: listener.reading) { _, reading in
            if confirmation.take(check.verdict(heard: reading.frequency)) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let cents = check.cents(heard: reading.frequency) ?? 0
                Log.audio.info("[LISTEN] confirmed \(check.writtenName, privacy: .public) at \(cents, privacy: .public) cents, inside \(check.tolerance, privacy: .public)")
                #if DEBUG
                FileLog.write(String(format: "[LISTEN] CONFIRMED %@ at %+.1f cents, inside %.0f", check.writtenName, cents, check.tolerance))
                #endif
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Text(isTuning ? "Tune your horn" : "Check a note")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.gold)
            Spacer(minLength: 8)
            Button("Done") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Which note to tune to. The director calls the concert pitch, so that
    /// is what the buttons say, and the line under them says the thing a new
    /// player does not know: what that is on the horn in their hands.
    private var choices: some View {
        VStack(spacing: 8) {
            Picker("Tuning note", selection: $chosen) {
                ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                    Text(target.choice ?? target.check.writtenName).tag(index)
                }
            }
            .pickerStyle(.segmented)
            Text("\(target.choice ?? "This note") on your \(check.instrument.shortName.lowercased()) is written \(check.writtenName). Play the note below.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The same staff and valves the chart pins at its top, so the note looks
    /// like the one that was just held.
    private var note: some View {
        HStack(spacing: 14) {
            StaffView(note: target.drawn ?? Note.named("B4") ?? Note.all[0], revealNote: target.drawn != nil)
                .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                Text(check.writtenName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(target.drawn == nil ? Theme.textDim : Theme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                ValveView(fingering: target.fingering ?? "?", diameter: 28)
            }
            .frame(width: 124, height: 100)
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var hearing: some View {
        VStack(spacing: 12) {
            switch listener.state {
            case .listening:
                listening
            case .asking:
                notice("Allow the microphone", "It listens to your horn and says whether you are on the note.")
            case .denied:
                notice("The microphone is off for this app",
                       "Turn it on in Settings to have your note checked. You can still see the note and hear it here.")
                button("Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            case .unavailable:
                notice("No microphone to listen with", "You can still see the note and hear it here.")
                button("Try again", systemImage: "mic") { listener.start(target: check.soundingFrequency) }
            case .idle:
                notice("Not listening", "")
                button("Listen", systemImage: "mic") { listener.start(target: check.soundingFrequency) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var listening: some View {
        let heard = listener.reading.frequency
        let verdict = check.verdict(heard: heard)
        let words = check.words(for: verdict, confirmed: confirmation.isConfirmed)
        let isRight: Bool = { if case .inTune = verdict { return true } else { return false } }()
        let tint = isRight || (confirmation.isConfirmed && verdict == .nothing) ? Theme.green : Theme.text

        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    if confirmation.isConfirmed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                    }
                    Text(words.headline)
                        .foregroundStyle(tint)
                }
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Always a line tall, so the scope under it does not jump up
                // and down as the words come and go.
                Text(words.detail.isEmpty ? " " : words.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .accessibilityElement(children: .combine)

            CentsMeter(cents: check.cents(heard: heard), inTune: check.tolerance)
                .frame(height: 34)

            Scope(trace: listener.reading.trace, isRight: isRight)
                .frame(height: 110)
            Text("Gold is the note, the other line is you. Lined up is in tune. Stretched wider is flat, squeezed is sharp.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reference: some View {
        VStack(spacing: 8) {
            button("Hear it", systemImage: "speaker.wave.2.fill") { hearIt() }
            // Said out loud, because the name on the page and the name of the
            // sound are different notes and a student with a tuner will ask.
            Text("Played at the pitch your \(prefs.instrument.shortName.lowercased()) makes for \(check.writtenName), which is concert \(check.soundingName). That is the sound to match.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func hearIt() {
        let seconds = 1.2
        listener.cover(for: seconds + 0.5)
        confirmation = NoteConfirmation()
        tone.reference(frequency: check.soundingFrequency, duration: seconds, volume: prefs.volume)
    }

    private func notice(_ headline: String, _ detail: String) -> some View {
        VStack(spacing: 4) {
            Text(headline)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 66)
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.gold)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Flat on the left, sharp on the right, and a band in the middle that counts
/// as in tune.
///
/// Half a semitone each way and no further. Past that the sound is a
/// different note and the words above say which, so the needle parks at the
/// end it went off and dims.
private struct CentsMeter: View {
    let cents: Double?
    let inTune: Double

    private let span = 50.0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let middle = width / 2
            let clamped = cents.map { min(span, max(-span, $0)) }
            let off = cents.map { abs($0) > span } ?? false
            let isRight = cents.map { abs($0) <= inTune } ?? false

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.green.opacity(isRight ? 0.55 : 0.25))
                    .frame(width: width * inTune / span, height: 14)
                    .offset(x: middle - width * inTune / span / 2)
                Rectangle()
                    .fill(Theme.textDim.opacity(0.6))
                    .frame(width: 1, height: 22)
                    .offset(x: middle)
                if let clamped {
                    Circle()
                        .fill(isRight ? Theme.green : Theme.gold)
                        .frame(width: 22, height: 22)
                        .opacity(off ? 0.4 : 1)
                        .offset(x: middle + width / 2 * clamped / span - 11)
                        .animation(.easeOut(duration: 0.12), value: clamped)
                }
            }
            .frame(height: geometry.size.height)
            .overlay(alignment: .bottomLeading) { label("flat") }
            .overlay(alignment: .bottomTrailing) { label("sharp") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cents.map { abs($0) <= inTune ? "In tune" : "\(Int(abs($0).rounded())) cents \($0 < 0 ? "flat" : "sharp")" } ?? "Nothing heard")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textDim)
            .offset(y: 12)
    }
}

/// The student's wave drawn over the note's.
///
/// A few cycles of the target as a plain sine, and whatever the microphone
/// heard across the same stretch of time, starting from the same point in its
/// cycle. See `PitchAnalysis.trace` for why that makes flat look stretched.
private struct Scope: View {
    let trace: [Float]
    let isRight: Bool

    private let cycles = Double(PitchAnalysis.traceCycles)

    var body: some View {
        Canvas { context, size in
            let middle = size.height / 2
            let reach = size.height / 2 - 8

            var target = Path()
            let steps = 240
            for step in 0...steps {
                let x = size.width * CGFloat(step) / CGFloat(steps)
                let y = middle - reach * 0.8 * CGFloat(sin(2 * Double.pi * cycles * Double(step) / Double(steps)))
                if step == 0 { target.move(to: CGPoint(x: x, y: y)) } else { target.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(target, with: .color(Theme.goldDim.opacity(0.8)), lineWidth: 2)

            guard trace.count > 1 else { return }
            var wave = Path()
            for (index, value) in trace.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(trace.count - 1)
                let y = middle - reach * CGFloat(value)
                if index == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(wave, with: .color(isRight ? Theme.green : Theme.text), lineWidth: 2)
        }
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityHidden(true)
    }
}
