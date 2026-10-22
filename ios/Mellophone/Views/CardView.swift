import OSLog
import SwiftUI

/// A chart as the director's own page, a few lines to a card, with the note
/// being played boxed on it (#43).
///
/// For sight reading: Sam reads songs he is still learning off lyre cards in a
/// flip folder, and the bar list of note names taught the names and not the
/// page. The page is drawn, never redrawn; the box comes from where the reader
/// found each notehead, and it follows the player's audio clock through
/// `PartModel.eventIDs(inSlot:)`, never a clock of its own.
///
/// Sideways, with every control in one row, because a lyre card is wider than
/// it is tall. Everything that changes what plays is the part screen's own,
/// handed in, so the two views cannot disagree about the range or the tempo.
struct CardView: View {
    let score: Score
    let chart: Chart
    @ObservedObject var model: PartModel
    @ObservedObject var player: PartPlayer
    /// The part screen's tempo control and its settings, the same views the
    /// Names view shows.
    let tempo: AnyView
    let settings: AnyView
    let play: () -> Void
    let hear: (PartTimeline.Entry) -> Void
    let check: (PartTimeline.Entry) -> Void
    let done: () -> Void
    let printCards: (LyreCardSheet) -> Void

    @EnvironmentObject private var prefs: Preferences
    @Environment(\.displayScale) private var displayScale
    @State private var strips: CardStrips?
    @State private var cardIndex = 0
    @State private var hidden = false
    @State private var showingSettings = false
    /// The bar a hold-and-drag started on, while it is being dragged.
    @State private var dragStart: Int?
    /// The paper chosen in the settings sheet, printed once the sheet is
    /// gone: a share sheet asked for while another sheet is still leaving is
    /// dropped.
    @State private var paper: LyreCardSheet?

    private var cards: [LyreCard] { LyreCards.cards(score.systems, linesPerCard: prefs.cardLines) }

    var body: some View {
        VStack(spacing: 6) {
            controlRow
            GeometryReader { space in
                cardPages(in: space.size)
            }
            footer
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            if strips == nil { strips = CardStrips(url: chart.url) }
            followPlayer(force: true)
            OrientationLock.set(.landscape, reason: "card view opened")
            #if DEBUG
            // -printCards letter|a4|cards walks the real path: open the
            // settings, pick the paper, let the sheet go, then the share sheet.
            if let raw = UserDefaults.standard.string(forKey: "printCards"), let sheet = LyreCardSheet(rawValue: raw) {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    showingSettings = true
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    paper = sheet
                    showingSettings = false
                }
            }
            #endif
            Log.score.info("[CARD] \(chart.title, privacy: .public): \(score.systems.count, privacy: .public) lines on \(cards.count, privacy: .public) cards of \(prefs.cardLines, privacy: .public)")
        }
        .onDisappear { OrientationLock.set(.portrait, reason: "card view closed") }
        // The card turns itself on the downbeat of its first bar. A card the
        // student swiped to by hand while it plays comes back at the next
        // note, the way their eyes come back to where the band is.
        .onChange(of: player.currentSlot) { _, _ in followPlayer() }
        // Play sets the bar before the count-in, so the card is already up
        // while the clicks go by; and a new start bar shows its card.
        .onChange(of: player.currentMeasure) { _, _ in followPlayer(force: true) }
        .onChange(of: model.from) { _, _ in followPlayer(force: true) }
        .onChange(of: prefs.cardLines) { _, _ in followPlayer(force: true) }
        .sheet(isPresented: $showingSettings, onDismiss: {
            guard let chosen = paper else { return }
            paper = nil
            printCards(chosen)
        }) { settingsSheet }
    }

    // MARK: - Following the music

    private func followPlayer(force: Bool = false) {
        guard player.isPlaying || force, let measure = player.currentMeasure ?? Optional(model.from),
              let index = LyreCards.index(holding: measure, in: cards), index != cardIndex else { return }
        let from = cardIndex
        cardIndex = index
        Log.score.info("[CARD] turned from card \(from + 1, privacy: .public) to \(index + 1, privacy: .public) at bar \(measure, privacy: .public)")
    }

    // MARK: - The row on top

    private var shown: PartTimeline.Entry? { model.entry(inSlot: player.currentSlot) }

    private var controlRow: some View {
        let event = shown?.event
        let fingering = event.flatMap { $0.isRest ? nil : Fingering.value(for: $0.writtenName, on: prefs.instrument) }
        return HStack(spacing: 8) {
            iconButton("xmark", label: "Close the chart") { done() }

            Group {
                if let beat = player.countInBeat {
                    noteBlock(name: "\(beat)", detail: "count in")
                } else {
                    noteBlock(name: hidden ? "?" : (event.map { $0.isRest ? "Rest" : $0.writtenName } ?? " "),
                              detail: event.map { "bar \($0.measure)" } ?? " ")
                }
            }
            .frame(width: 88, alignment: .leading)

            ValveView(fingering: hidden ? " " : (fingering ?? (event?.isRest == false ? "?" : " ")),
                      revealed: !hidden, diameter: 24)
                .frame(width: 92)

            smallButton(hidden ? "Show" : "Hide") {
                hidden.toggle()
                Log.score.info("[CARD] note name \(hidden ? "hidden" : "shown", privacy: .public)")
            }
            checkButton

            Spacer(minLength: 0)
            tempo
            iconButton("gearshape", label: "Settings, the bar list and printing") { showingSettings = true }
            playButton
        }
        .frame(height: 48)
    }

    private func noteBlock(name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(shown?.event.outOfRangeName == nil ? Theme.gold : Theme.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
        }
    }

    /// Holding it checks the note shown, the same as holding the note on the
    /// card. A tap only says how, since a tap that opened the microphone by
    /// accident would stop the music.
    private var checkButton: some View {
        Text("Hold: check")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onLongPressGesture {
                guard let entry = shown, !entry.event.isRest else { return }
                check(entry)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Hold to check yourself against the note shown")
    }

    private var playButton: some View {
        Button {
            if player.isPlaying { player.stop() } else { play() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                Text(player.isPlaying ? "Stop" : "Play")
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(player.isPlaying ? Theme.text : Color.black)
            .frame(width: 92, height: 40)
            .background(player.isPlaying ? Theme.surface : Theme.gold)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 36, height: 36)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - The cards

    private func cardPages(in size: CGSize) -> some View {
        TabView(selection: $cardIndex) {
            ForEach(cards, id: \.index) { card in
                cardPage(card, in: size).tag(card.index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: cardIndex) { old, new in
            if player.isPlaying, new != LyreCards.index(holding: player.currentMeasure ?? 0, in: cards) {
                Log.score.info("[CARD] swiped by hand from card \(old + 1, privacy: .public) to \(new + 1, privacy: .public) while playing")
            }
        }
    }

    /// One card, as large as the space allows. Four PEAK lines are taller at
    /// full width than a phone on its side, so the card is fitted to whichever
    /// runs out first and centred.
    private func cardPage(_ card: LyreCard, in size: CGSize) -> some View {
        let full = CardGeometry(systems: score.systems, card: card, width: size.width)
        let width = full.height > size.height ? size.width * size.height / full.height : size.width
        let geometry = CardGeometry(systems: score.systems, card: card, width: width)
        let sounding = model.eventIDs(inSlot: player.currentSlot)
        let lit = score.events.filter { sounding.contains($0.id) && $0.place.map { card.systems.contains($0.system) } == true }
        let picked = player.isPlaying ? nil : model.picked?.event.place.flatMap { card.systems.contains($0.system) ? $0 : nil }
        return ZStack(alignment: .topLeading) {
            Color.white
            ForEach(Array(card.systems), id: \.self) { index in
                let frame = geometry.stripFrame(index)
                if let image = strips?.image(score.systems[index], index: index, size: frame.size,
                                             scale: geometry.scale, displayScale: displayScale) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            suspectMarks(geometry)
            loopBracket(card, geometry)
            highlight(lit.compactMap(\.place).map(geometry.box), size: CGSize(width: width, height: geometry.height))
            if let picked {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Theme.gold, lineWidth: 2)
                    .frame(width: geometry.box(picked).width, height: geometry.box(picked).height)
                    .offset(x: geometry.box(picked).minX, y: geometry.box(picked).minY)
            }
        }
        .frame(width: width, height: geometry.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(CardTouchLayer(onTap: { tap($0, geometry) },
                                onHoldBegan: { holdBegan($0, geometry) },
                                onHoldEnded: { holdEnded($0, geometry) }))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Card \(card.index + 1) of \(cards.count), bars \(card.firstMeasure) to \(card.lastMeasure)")
    }

    /// The page dimmed round the notes sounding, and a gold box on each, so
    /// the eye lands on the note without the page being covered. Nothing is
    /// dimmed while it is stopped: then the page is for reading.
    private func highlight(_ boxes: [CGRect], size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if !boxes.isEmpty {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    for box in boxes { path.addRoundedRect(in: box, cornerSize: CGSize(width: 3, height: 3)) }
                }
                .fill(Color.black.opacity(0.3), style: FillStyle(eoFill: true))
                ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Theme.gold, lineWidth: 2.5)
                        .frame(width: box.width, height: box.height)
                        .offset(x: box.minX, y: box.minY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// A bar whose beats did not add up is outlined, the way the list marks
    /// it, and still shown and played as read: the page is to be trusted.
    private func suspectMarks(_ geometry: CardGeometry) -> some View {
        let frames = geometry.barFrames(score.suspectMeasures)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                Rectangle()
                    .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .allowsHitTesting(false)
    }

    /// The bars being looped, as a gold bar over each one's top edge.
    private func loopBracket(_ card: LyreCard, _ geometry: CardGeometry) -> some View {
        let spans: [CGRect] = model.loop ? card.systems.flatMap { index -> [CGRect] in
            let frame = geometry.stripFrame(index)
            return score.systems[index].bars
                .filter { $0.measure >= model.from && $0.measure <= model.to }
                .map { bar in
                    let x0 = geometry.point(x: bar.x0, y: 0, system: index).x
                    let x1 = geometry.point(x: bar.x1, y: 0, system: index).x
                    return CGRect(x: x0, y: frame.minY + 1, width: x1 - x0, height: 4)
                }
        } : []
        return ZStack(alignment: .topLeading) {
            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                Rectangle().fill(Theme.gold)
                    .frame(width: span.width, height: span.height)
                    .offset(x: span.minX, y: span.minY)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Touch

    private func entry(for event: ScoreEvent) -> PartTimeline.Entry? {
        model.rows.lazy.flatMap(\.entries).first { $0.id == event.id }
    }

    /// A tap on a note sounds it; a tap on a bar starts there. Between the
    /// two, a tap on the staff next to a note does nothing on purpose, the
    /// same rule as the bar list's gaps.
    private func tap(_ point: CGPoint, _ geometry: CardGeometry) {
        if let event = geometry.note(at: point, among: model.tappableEvents), let entry = entry(for: event) {
            Log.score.info("[CARD] tapped \(event.writtenName, privacy: .public) in bar \(event.measure, privacy: .public)")
            hear(entry)
        } else if let bar = geometry.measure(at: point) {
            let playing = player.isPlaying
            player.stop()
            model.start(at: bar)
            Log.score.info("[CARD] start moved to bar \(bar, privacy: .public)\(playing ? ", playing from there" : "", privacy: .public)")
            if playing { play() }
        } else {
            Log.score.debug("[CARD] tap at \(point.x, privacy: .public), \(point.y, privacy: .public) is on no note and no bar")
        }
    }

    /// Hold a note to check it. Hold a bar and drag across to loop those bars:
    /// it has to start with a hold, or it would fight the swipe that turns
    /// the card.
    private func holdBegan(_ point: CGPoint, _ geometry: CardGeometry) {
        if let event = geometry.note(at: point, among: model.tappableEvents), let entry = entry(for: event) {
            dragStart = nil
            Log.score.info("[CARD] held \(event.writtenName, privacy: .public) in bar \(event.measure, privacy: .public) to check it")
            check(entry)
        } else {
            dragStart = geometry.measure(at: point)
            if dragStart == nil { Log.score.debug("[CARD] hold on no note and no bar") }
        }
    }

    private func holdEnded(_ point: CGPoint, _ geometry: CardGeometry) {
        defer { dragStart = nil }
        guard let start = dragStart else { return }
        let end = geometry.measure(at: point) ?? start
        player.stop()
        model.start(at: min(start, end))
        model.end(at: max(start, end))
        model.loop = true
        Log.score.info("[CARD] looping bars \(min(start, end), privacy: .public) to \(max(start, end), privacy: .public)")
    }

    // MARK: - Under the card

    private var footer: some View {
        HStack(spacing: 10) {
            if let card = cards.indices.contains(cardIndex) ? cards[cardIndex] : nil {
                // With a repeat in the range the card turns BACK mid-run,
                // so the footer says the app means to (#46).
                Text("CARD \(card.index + 1) OF \(cards.count)  ·  BARS \(card.firstMeasure) TO \(card.lastMeasure)"
                     + (model.repeatNote == nil ? "" : "  ·  TAKES THE REPEAT"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            if cards.count > 1 {
                HStack(spacing: 6) {
                    ForEach(cards, id: \.index) { card in
                        Circle()
                            .fill(card.index == cardIndex ? Theme.gold : Theme.surface)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            Spacer()
            Text(score.suspectMeasures.isEmpty
                 ? "Tap a note to hear it, hold to check. Tap a bar to start there, hold and drag to loop."
                 : "Red bars did not add up when read. They play as read; trust the page.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(height: 18)
        .padding(.bottom, 2)
    }

    // MARK: - Settings

    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(chart.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.gold)
                            .lineLimit(2)
                        Spacer()
                        InstrumentChip()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRINT LYRE CARDS (17.8 x 13.4 CM, NOTHING UNDER THE RINGS)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                        HStack(spacing: 8) {
                            ForEach(LyreCardSheet.allCases) { sheet in
                                option(sheet.label, selected: false) {
                                    paper = sheet
                                    showingSettings = false
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LINES PER CARD")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                        HStack(spacing: 8) {
                            ForEach(Array(LyreCards.lineChoices), id: \.self) { lines in
                                option("\(lines)", selected: prefs.cardLines == lines) {
                                    prefs.cardLines = lines
                                    Log.score.info("[CARD] \(lines, privacy: .public) lines per card")
                                }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        option("Count in", selected: prefs.partCountIn) {
                            player.stop()
                            prefs.partCountIn.toggle()
                        }
                        option("Loop", selected: model.loop) {
                            player.stop()
                            model.loop.toggle()
                        }
                    }
                    settings
                }
                .padding(16)
            }
            .background(Theme.bg)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false }
                }
            }
        }
        .environmentObject(prefs)
        .preferredColorScheme(.dark)
    }

    private func option(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selected ? Theme.gold : Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
