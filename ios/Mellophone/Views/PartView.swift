import OSLog
import SwiftUI

/// One imported chart: hear it, follow it, slow it down, loop the hard bars.
///
/// The staff, the fingering and the transport are PINNED and the bars scroll
/// under them. The list follows the music, and with everything in one scroll
/// the note being played and the Stop button would both leave the screen eight
/// bars in.
struct PartView: View {
    let chart: Chart
    /// Called when the chart turned out to be unreadable, so the library can
    /// drop the copy. A file that cannot be read is not worth keeping a row
    /// for, since tapping it would only say the same thing again.
    var onUnreadable: (Chart) -> Void = { _ in }

    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PartModel()
    /// Owned by the charts card and handed in, never made here. See the note
    /// on `PartPlayer` for why a player per chart is not an option.
    @ObservedObject var player: PartPlayer

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                switch model.state {
                case .loading:
                    loading
                case .failed(let message):
                    failure(message)
                case .ready(let score):
                    ready(score)
                }
            }
        }
        .task { await load() }
        .onDisappear { player.stop() }
    }

    private func load() async {
        await model.load(chart)
        if case .failed = model.state { onUnreadable(chart) }
        #if DEBUG
        // Presses Play without a finger, for the same reason -autoPlayScale
        // exists: the first render on a cold engine is where this kind of
        // screen has failed before, and a test never sees a cold engine.
        //   xcrun simctl launch booted com.massfeller.mellophone \
        //     -startTab scales -openChart /path/to/chart.pdf -autoPlayPart YES
        // -partFrom 16 starts at that bar, to screenshot notes and not the rests
        // most parts open with.
        let from = UserDefaults.standard.integer(forKey: "partFrom")
        if from > 0 { model.start(at: from) }
        // -tapNote 3 taps the third note in the list, to see and hear a tapped
        // note without a finger: the simulator has no way to be touched from a
        // script.
        let tap = UserDefaults.standard.integer(forKey: "tapNote")
        if tap > 0, let entry = model.rows.flatMap(\.entries).filter({ $0.frequency != nil }).dropFirst(tap - 1).first {
            FileLog.write("[PART] tapNote \(tap): \(entry.event.writtenName) in bar \(entry.event.measure)")
            hear(entry)
        }
        if UserDefaults.standard.bool(forKey: "autoPlayPart"), case .ready = model.state {
            FileLog.write("[PART] autoPlay requested for \(chart.title)")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            play()
        }
        #endif
    }

    private func play() {
        guard let timeline = model.prepare(bpm: prefs.partTempo) else { return }
        // Two lines at once are two tones summed, so each gets half the level.
        // Otherwise "Both" is louder than either line and clips at a volume
        // that was fine a moment ago.
        let voices = model.voice == .all ? max(1, model.voiceCount) : 1
        player.room = prefs.partRoom
        player.play(timeline, countIn: prefs.partCountIn, loop: model.loop,
                    volume: prefs.volume / Double(voices))
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Text(chart.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
                .truncationMode(.middle)
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

    private var loading: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().tint(Theme.gold)
            Text("Reading the chart")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "doc.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textDim)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - The part

    private func ready(_ score: Score) -> some View {
        VStack(spacing: 0) {
            nowPlaying
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        summary(score)
                        controls(score)
                        bars
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .onChange(of: player.currentMeasure) { _, measure in
                    guard let measure, let row = model.row(holding: measure) else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(row.id, anchor: .center)
                    }
                }
            }

            transport
        }
    }

    /// The note sounding now, or the one Play would start on.
    private var nowPlaying: some View {
        let entry = model.entry(inSlot: player.currentSlot)
        let event = entry?.event
        // The staff draws the app's row for the pitch, but the row the PAGE
        // spelled is used when there is one, so a written sharp is drawn as a
        // sharp and not as the flat the table files it under.
        let drawn = event.flatMap { Note.named($0.writtenName) ?? $0.note }
        let name = event.map { $0.isRest ? "Rest" : $0.writtenName } ?? " "
        let fingering = event.flatMap { $0.isRest ? nil : Fingering.value(for: $0.writtenName, on: prefs.instrument) }

        return HStack(spacing: 14) {
            // A rest still draws a staff, and the staff draws ledger lines for
            // whatever note it is handed even when the note itself is hidden.
            // The middle line needs none, so a rest is an empty staff.
            StaffView(note: drawn ?? Note.named("B4") ?? Note.all[0], revealNote: drawn != nil)
                .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                if let beat = player.countInBeat {
                    Text("\(beat)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.gold)
                        .monospacedDigit()
                    Text("count in")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                } else if let beat = player.currentBeat, let rest = restBeingCounted {
                    // Through a bar of rest nothing on the screen moves, and a
                    // screen that sits still for 30 seconds looks broken. So it
                    // counts, the way the count-in does and the way a player
                    // does in their head: the beat large, the bar under it.
                    Text("\(beat)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(beat == 1 ? Theme.gold : Theme.text)
                        .monospacedDigit()
                    Text(restLabel(rest, sounding: player.currentMeasure))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(event?.outOfRangeName == nil ? Theme.gold : Theme.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ValveView(fingering: fingering ?? (event?.isRest == false ? "?" : " "), diameter: 28)
                }
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

    /// The row of whole-bar rest the player is inside, if it is inside one.
    /// A quarter rest in a bar of notes is not counted this way: the notes
    /// around it are already moving, and a digit flashing up between them
    /// would be read as a fingering.
    private var restBeingCounted: PartModel.Row? {
        guard let bar = player.currentMeasure, let row = model.row(holding: bar), row.isRest else { return nil }
        return row
    }

    private func summary(_ score: Score) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.describe(score))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            // Said out loud, per the design: the reader follows the page top to
            // bottom and does not know what a repeat sign means yet. A student
            // who is not told will think the app lost its place.
            Text("Plays the page straight through, top to bottom. Repeats, endings and codas are not followed.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            if !score.suspectMeasures.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.red)
                    // The whole point of the bar check: a rhythm the reader is
                    // not sure of is marked, not played as if it were right.
                    Text("\(score.suspectMeasures.count) \(score.suspectMeasures.count == 1 ? "bar does" : "bars do") not add up and \(score.suspectMeasures.count == 1 ? "is" : "are") outlined in red. The rhythm there may be wrong, so trust the page over the app.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: - Controls

    /// Only what is set once per sitting lives up here. Tempo, count in and
    /// loop are changed between every run of a hard passage, so they are
    /// pinned with the transport where a thumb already is.
    private func controls(_ score: Score) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.voiceCount > 1 {
                section("Which line") {
                    HStack(spacing: 8) {
                        ForEach(model.voiceChoices) { choice in
                            chip(choice.label, selected: model.voice == choice.voice) {
                                player.stop()
                                model.voice = choice.voice
                            }
                        }
                    }
                }
            }

            range

            section("Sound") {
                HStack(spacing: 8) {
                    ForEach(PartRoom.allCases) { room in
                        // No stop: the room is changed while it plays, which
                        // is the only way to hear what the choice does.
                        chip(room.label, selected: prefs.partRoom == room) {
                            prefs.partRoom = room
                            player.room = room
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var tempo: some View {
        HStack(spacing: 6) {
            stepButton("minus", label: "Slower by 5", size: 40) { nudgeTempo(-5) }
            VStack(spacing: 0) {
                Text("\(prefs.partTempo)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
                // Says what the number counts. The reader does not read the
                // tempo mark, so this is the student's number, and 120 means
                // something different in 6/8 than in 4/4.
                Text(model.pulseLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 74)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tempo \(prefs.partTempo) \(model.pulseLabel) per minute")
            stepButton("plus", label: "Faster by 5", size: 40) { nudgeTempo(5) }
        }
    }

    private func nudgeTempo(_ delta: Int) {
        player.stop()
        prefs.partTempo = min(220, max(40, prefs.partTempo + delta))
    }

    private var range: some View {
        section("Bars") {
            HStack(spacing: 8) {
                barStepper("From", value: model.from) { model.moveFrom(by: $0); player.stop() }
                barStepper("To", value: model.to) { model.moveTo(by: $0); player.stop() }
            }
            // Said out loud, because a range that quietly starts at bar 16
            // looks like the reader lost the first page.
            if model.barsSkippedBeforeEntrance > 0 {
                Text("Starts at bar \(model.from), where you come in. \(model.barsSkippedBeforeEntrance == 1 ? "1 bar" : "\(model.barsSkippedBeforeEntrance) bars") of rest before it.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Text("Tap a note to hear it. Tap a bar number to start there, hold it to end there.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !model.isWholePart {
                    Button {
                        player.stop()
                        model.selectWholePart()
                    } label: {
                        Text("Whole part")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func barStepper(_ title: String, value: Int, move: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            stepButton("minus", label: "\(title) one bar earlier", size: 36) { move(-1) }
            VStack(spacing: 0) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                Text("\(value)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            stepButton("plus", label: "\(title) one bar later", size: 36) { move(1) }
        }
        .padding(6)
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: - Bars

    private var bars: some View {
        let current = model.eventIDs(inSlot: player.currentSlot)
        return LazyVStack(spacing: 6) {
            ForEach(model.rows) { row in
                barRow(row, current: current)
                    .id(row.id)
            }
        }
    }

    private func barRow(_ row: PartModel.Row, current: Set<UUID>) -> some View {
        let inRange = row.last >= model.from && row.first <= model.to
        // The bar sounding now, when it is one of this row's.
        let sounding = player.currentMeasure.flatMap { row.first <= $0 && $0 <= row.last ? $0 : nil }
        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                Text(row.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(row.isSuspect ? Theme.red : Theme.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if row.isSuspect {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.red)
                }
            }
            // Drawn as a key, because it is one now: the notes beside it
            // answer a tap themselves, so this is what moves the range.
            .frame(width: 44, height: 42)
            .background(Theme.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            if row.isRest {
                Text(restLabel(row, sounding: sounding))
                    .font(.system(size: 12, weight: sounding == nil ? .regular : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(sounding == nil ? Theme.textDim : Theme.gold)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(row.entries) { entry in
                        noteChip(entry, playing: current.contains(entry.id))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The notes belong to the notes. A tap that lands in the gap
                // between two of them was aimed at one of them, and letting it
                // through to the row would move the start of the range under
                // a student who only wanted to hear a pitch.
                .contentShape(Rectangle())
                .onTapGesture {}
                .onLongPressGesture {}
            }
        }
        .padding(8)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(row.isSuspect ? Theme.red.opacity(0.8) : (sounding != nil && row.isRest ? Theme.goldDim : Theme.cardBorder),
                        lineWidth: row.isSuspect ? 1.5 : 1)
        )
        .opacity(inRange ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture {
            player.stop()
            model.start(at: row.first)
        }
        .onLongPressGesture {
            player.stop()
            model.end(at: row.last)
        }
        // Contained and not combined: each note is its own thing to press now,
        // and one element for the whole bar would hide them from VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.first == row.last ? "Bar \(row.first)" : "Bars \(row.first) to \(row.last)")
        .accessibilityHint("Tap the bar number to start here, hold it to end here")
    }

    /// Sound one note and leave it on the staff.
    private func hear(_ entry: PartTimeline.Entry) {
        guard let frequency = model.pick(entry) else { return }
        player.room = prefs.partRoom
        player.sound(frequency: frequency, volume: prefs.volume)
    }

    /// Counting rests is half of playing a part, and it is the half a student
    /// loses their place in. A long rest counts its bars as they go by, the
    /// way a player counts them: "5 of 15".
    private func restLabel(_ row: PartModel.Row, sounding: Int?) -> String {
        let bars = row.last - row.first + 1
        guard bars > 1 else { return "rest" }
        guard let sounding else { return "rest for \(bars) bars" }
        return "rest, bar \(sounding - row.first + 1) of \(bars)"
    }

    private func noteChip(_ entry: PartTimeline.Entry, playing: Bool) -> some View {
        let event = entry.event
        let outOfRange = event.outOfRangeName != nil
        let fingering = event.isRest ? nil : Fingering.value(for: event.writtenName, on: prefs.instrument)
        let picked = !playing && model.picked?.id == entry.id
        return VStack(spacing: 1) {
            Text(event.isRest ? "rest" : event.writtenName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(playing ? Color.black : (event.isRest || outOfRange ? Theme.textDim : Theme.text))
            // A pitch outside the chart still sounds, and still shows its
            // name. It has no fingering to give, and says so plainly: an
            // empty space would read as "open".
            Text(event.isRest ? " " : (fingering ?? "n/a"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(playing ? Color.black.opacity(0.65) : (outOfRange ? Theme.textDim : Theme.goldDim))
        }
        // Wider for longer notes, so the row has the rhythm's shape without
        // drawing notation the reader would then have to get right.
        .frame(width: model.chipWidth(for: entry), height: 42)
        .background(playing ? Theme.gold : Theme.surface.opacity(event.isRest ? 0.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // Outlined and not filled: filled gold means "sounding now in the
        // run", and a note that was tapped is on the staff but not moving.
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.gold, lineWidth: 2)
                .opacity(picked ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { hear(entry) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.isRest ? "Rest" : "\(event.writtenName), \(fingering ?? "no fingering")")
        .accessibilityHint(event.isRest ? "" : "Tap to hear it")
        .accessibilityAddTraits(event.isRest ? [] : .isButton)
    }

    // MARK: - Transport

    private var transport: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tempo
                chip("Count in", selected: prefs.partCountIn) {
                    player.stop()
                    prefs.partCountIn.toggle()
                }
                chip("Loop", selected: model.loop) {
                    player.stop()
                    model.loop.toggle()
                }
            }
            playAndStop
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.bg)
    }

    private var playAndStop: some View {
        HStack(spacing: 10) {
            Button(action: play) {
                transportLabel(model.loop ? "Play loop" : "Play", systemImage: "play.fill", prominent: true)
            }
            .buttonStyle(.plain)
            .disabled(player.isPlaying)
            .opacity(player.isPlaying ? 0.5 : 1)

            Button { player.stop() } label: {
                transportLabel("Stop", systemImage: "stop.fill", prominent: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func transportLabel(_ title: String, systemImage: String, prominent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(prominent ? Color.black : Theme.text)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(prominent ? Theme.gold : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Small pieces, in the Metronome tab's shapes

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
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func stepButton(_ symbol: String, label: String, size: CGFloat = 44,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: size, height: size)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                // Drawn at `size` but hit at 44, Apple's minimum, because this
                // gets pressed with the side of a thumb by someone holding a
                // horn in the other hand.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Held down, it keeps going. 40 to 220 in fives is a lot of taps.
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}

/// What the part screen is showing and what it would play.
///
/// The player knows nothing about bars, voices or ranges. It is handed a
/// timeline and plays it. Everything the student can change lives here, and
/// changing any of it is just a different timeline on the next Play.
@MainActor
final class PartModel: ObservableObject {
    enum State {
        case loading
        case failed(String)
        case ready(Score)
    }

    /// One line of the bar list. Usually one bar; a run of empty bars is one
    /// row, because sixteen rows that each say "rest" are sixteen rows to
    /// scroll past to reach the next note.
    struct Row: Identifiable {
        let first: Int
        let last: Int
        let entries: [PartTimeline.Entry]
        let isRest: Bool
        let isSuspect: Bool

        var id: Int { first }
        var label: String { first == last ? "\(first)" : "\(first) to \(last)" }
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var rows: [Row] = []
    @Published private(set) var from = 1
    @Published private(set) var to = 1
    @Published var loop = false
    @Published var voice: PartVoice = .line(0) {
        didSet { if voice != oldValue { rebuildRows() } }
    }

    private(set) var voiceCount = 1
    /// What the tempo number counts, as it reads under the number.
    private(set) var pulseLabel = "quarter notes"
    /// Every bar number the part has, in order. The steppers walk THIS and not
    /// the integers, since a chart is free to skip a number.
    private var barNumbers: [Int] = []
    private var score: Score = .empty
    /// The timeline last handed to the player, kept so a slot number coming
    /// back from it can be turned into the events to light.
    private var playing: PartTimeline?
    private var idsBySlot: [Int: Set<UUID>] = [:]
    private var leadBySlot: [Int: PartTimeline.Entry] = [:]

    /// The note the student tapped to hear. It stays on the staff, with its
    /// valves, until they play the passage or move where it starts: the point
    /// of tapping it was to look at it with the horn up.
    @Published private(set) var picked: PartTimeline.Entry?

    var isWholePart: Bool { from == barNumbers.first && to == barNumbers.last }

    /// The first bar with a note in it, or nil for a part that is all rests.
    private(set) var entrance: Int?

    /// How many bars of rest the range is skipping at the front, when it starts
    /// exactly where the player comes in. Zero otherwise, which is what hides
    /// the line that explains it.
    var barsSkippedBeforeEntrance: Int {
        guard let entrance, from == entrance, let index = barNumbers.firstIndex(of: entrance) else { return 0 }
        return index
    }

    struct VoiceChoice: Identifiable {
        let voice: PartVoice
        let label: String
        var id: PartVoice { voice }
    }

    /// "Top" and "Bottom" for the usual two way split, which is how a section
    /// talks about it. Numbers only when there are more lines than that.
    var voiceChoices: [VoiceChoice] {
        let lines = voiceCount == 2
            ? [VoiceChoice(voice: .line(0), label: "Top"), VoiceChoice(voice: .line(1), label: "Bottom")]
            : (0..<voiceCount).map { VoiceChoice(voice: .line($0), label: "Line \($0 + 1)") }
        return lines + [VoiceChoice(voice: .all, label: voiceCount == 2 ? "Both" : "All")]
    }

    // MARK: - Loading

    func load(_ chart: Chart) async {
        let url = chart.url
        // Off the main thread: a four page chart is a few thousand glyphs and
        // paths to walk, and a frozen screen right after picking a file reads
        // as the app having crashed.
        let result = await Task.detached(priority: .userInitiated) {
            Result { try ScoreImporter.readOrThrow(url: url) }
        }.value

        switch result {
        case .success(let score):
            adopt(score)
        case .failure(let error):
            state = .failed(Self.message(for: error))
        }
    }

    /// Take a score that has already been read. Split from `load` so the bar
    /// list and the range can be tested on a score built by hand, with rests
    /// and flagged bars in it that no committed fixture has.
    func adopt(_ score: Score) {
        self.score = score
        voiceCount = max(1, score.voiceCount)
        pulseLabel = "\(Pulse.of(score.timeSignature).name)s"
        barNumbers = Self.barNumbers(in: score)
        // Open where the player comes in, not at bar 1. A horn part routinely
        // sits out the first phrase, and a student alone with a phone has no
        // band to count against: Sam's opener starts with fifteen bars of rest,
        // which was 36 seconds of nothing after the count-in and read as the
        // app having broken. "Whole part" still goes back to bar 1.
        entrance = score.events
            .first { PartTimeline.frequency(of: $0) != nil }
            .map(\.measure)
            .flatMap { barNumbers.contains($0) ? $0 : nil }
        from = entrance ?? barNumbers.first ?? 1
        to = barNumbers.last ?? 1
        rebuildRows()
        state = .ready(score)

        if let entrance {
            Log.score.info("[PART] \(self.barNumbers.count, privacy: .public) bars, opening at bar \(entrance, privacy: .public), the first with a note in it")
        } else {
            // Nothing to skip to. Shown whole, so the student sees a page of
            // rests and not an empty range.
            Log.score.error("[PART] \(self.barNumbers.count, privacy: .public) bars and not one note in them, opening at bar \(self.from, privacy: .public)")
        }
    }

    /// One sentence per failure, each sending the student somewhere different.
    static func message(for error: Error) -> String {
        switch error as? ImportError {
        case .noReadableNotation:
            return "This PDF has no readable notation in it. A scan or a photo of a page cannot be read. It has to be the PDF the notation program made."
        case .noStaffFound:
            return "Could not find a staff on this page."
        case .cannotOpenFile, .none:
            return "Could not open that file. If it lives in OneDrive, mark it Available Offline there and try again."
        }
    }

    func describe(_ score: Score) -> String {
        let key: String
        switch score.keySignature {
        case 0: key = "no sharps or flats"
        case 1: key = "1 sharp"
        case -1: key = "1 flat"
        case let sharps where sharps > 0: key = "\(sharps) sharps"
        default: key = "\(-score.keySignature) flats"
        }
        let count = barNumbers.count
        return "\(count) \(count == 1 ? "bar" : "bars"), \(score.timeSignature.beats)/\(score.timeSignature.unit), \(key)"
    }

    private static func barNumbers(in score: Score) -> [Int] {
        var numbers: [Int] = []
        for event in score.events where event.voice == 0 && numbers.last != event.measure {
            numbers.append(event.measure)
        }
        return numbers
    }

    // MARK: - The bar list

    private func rebuildRows() {
        // The rows are about to be made again, out of new entries. A pick from
        // the old ones would name a note that may not be in this line at all.
        picked = nil
        guard let first = barNumbers.first, let last = barNumbers.last else { rows = []; return }
        // Laid out at a fixed tempo. Only the order and the grouping are used
        // here, and neither depends on how fast it goes.
        let whole = PartTimeline(score: score, voice: voice, measures: first...last, bpm: 60)
        let byBar = Dictionary(grouping: whole.entries, by: \.event.measure)

        var rows: [Row] = []
        for number in barNumbers {
            let entries = byBar[number] ?? []
            let isRest = entries.allSatisfy(\.event.isRest)
            let isSuspect = score.suspectMeasures.contains(number)
            // A flagged bar is never folded into a run, even an empty one. It
            // is flagged because the reader is unsure what is in it.
            if isRest, !isSuspect, let previous = rows.last, previous.isRest, !previous.isSuspect {
                rows[rows.count - 1] = Row(first: previous.first, last: number,
                                           entries: previous.entries + entries,
                                           isRest: true, isSuspect: false)
            } else {
                rows.append(Row(first: number, last: number, entries: entries,
                                isRest: isRest, isSuspect: isSuspect))
            }
        }
        self.rows = rows
    }

    func row(holding measure: Int) -> Row? {
        rows.first { $0.first <= measure && measure <= $0.last }
    }

    /// A quarter note is the narrowest a name and a fingering fit in, and a
    /// whole note is not allowed to take the row by itself.
    func chipWidth(for entry: PartTimeline.Entry) -> CGFloat {
        let quarters = entry.event.durationBeats * 4 / Double(score.beatUnit(of: entry.event.measure))
        return min(112, max(40, 26 + 18 * quarters))
    }

    // MARK: - The range

    func start(at bar: Int) {
        from = bar
        if to < from { to = barNumbers.last ?? bar }
        picked = nil
    }

    func end(at bar: Int) {
        to = bar
        if from > to { from = barNumbers.first ?? bar }
    }

    func moveFrom(by step: Int) {
        guard let moved = neighbour(of: from, by: step), moved <= to else { return }
        from = moved
        picked = nil
    }

    func moveTo(by step: Int) {
        guard let moved = neighbour(of: to, by: step), moved >= from else { return }
        to = moved
    }

    func selectWholePart() {
        from = barNumbers.first ?? 1
        to = barNumbers.last ?? 1
        picked = nil
    }

    // MARK: - One note

    /// Put a tapped note on the staff and hand back the pitch to sound.
    ///
    /// Nil for a rest, which leaves whatever was showing alone: there is
    /// nothing to hear and nothing to finger.
    @discardableResult
    func pick(_ entry: PartTimeline.Entry) -> Double? {
        guard let frequency = entry.frequency else { return nil }
        picked = entry
        Log.score.info("[PART] picked \(entry.event.writtenName, privacy: .public) in bar \(entry.event.measure, privacy: .public)")
        return frequency
    }

    private func neighbour(of bar: Int, by step: Int) -> Int? {
        guard let index = barNumbers.firstIndex(of: bar) else { return nil }
        let moved = index + step
        return barNumbers.indices.contains(moved) ? barNumbers[moved] : nil
    }

    // MARK: - Playing

    /// The timeline for what is selected right now, remembered so the
    /// player's slot numbers can be read back.
    func prepare(bpm: Int) -> PartTimeline? {
        guard from <= to, !barNumbers.isEmpty else { return nil }
        let timeline = PartTimeline(score: score, voice: voice, measures: from...to, bpm: Double(bpm))
        picked = nil
        playing = timeline
        idsBySlot = Dictionary(grouping: timeline.entries, by: \.slot).mapValues { Set($0.map(\.id)) }
        leadBySlot = Dictionary(timeline.entries.map { ($0.slot, $0) }) { first, _ in first }
        return timeline
    }

    func eventIDs(inSlot slot: Int?) -> Set<UUID> {
        slot.flatMap { idsBySlot[$0] } ?? []
    }

    /// The entry to show on the staff: the one sounding, or with nothing
    /// playing, the note the student tapped, or failing that the first note
    /// Play would start on.
    func entry(inSlot slot: Int?) -> PartTimeline.Entry? {
        if let slot, let entry = leadBySlot[slot] { return entry }
        if let picked { return picked }
        return rows.first { $0.last >= from }?.entries.first { $0.event.measure >= from }
    }
}
