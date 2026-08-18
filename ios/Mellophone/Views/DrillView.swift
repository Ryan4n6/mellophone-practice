import SwiftUI

struct DrillView: View {
    @EnvironmentObject private var prefs: Preferences
    @StateObject private var model = DrillModel()

    var body: some View {
        PageScaffold(title: "Note Recognition Drill", subtitle: "See a note, name it") {
            VStack(spacing: 16) {
                options
                stats
                StaffView(note: model.question)
                feedback
                answerGrid
                Button {
                    model.skip()
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .card()

            Button {
                model.reset()
            } label: {
                Text("Reset Score")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .onAppear { model.bind(prefs) }
    }

    private var options: some View {
        VStack(spacing: 8) {
            toggle("Include sharps", $model.includeSharps)
            toggle("Include flats", $model.includeFlats)
            toggle("Play audio", $model.playAudio)
        }
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
        }
        .tint(Theme.gold)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat("\(model.correct)", "Correct")
            stat("\(model.total)", "Total")
            stat(model.accuracy, "Accuracy")
            stat("\(model.streak)", "Streak")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.gold)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
    }

    private var feedback: some View {
        Text(model.feedback ?? " ")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(model.lastAnswerWasCorrect == true ? Theme.green : Theme.red)
            .frame(height: 20)
            .animation(.easeOut(duration: 0.12), value: model.feedback)
    }

    /// The deliberate divergence from the web version.
    ///
    /// There, you type "Bb4" into a text field. On a phone, while holding a
    /// mellophone, that is the wrong input device for the situation: it costs a
    /// keyboard, two hands and a shifted layout to answer a question that should
    /// take one thumb. Same question, same scoring, same enharmonic acceptance.
    private var answerGrid: some View {
        FlowLayout(spacing: 6) {
            ForEach(model.answerChoices) { note in
                Button {
                    model.answer(note)
                } label: {
                    Text(note.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isShowingResult)
                .opacity(model.isShowingResult ? 0.4 : 1)
            }
        }
    }
}

final class DrillModel: ObservableObject {
    @Published private(set) var question: Note = Note.named("C5") ?? Note.all[0]
    @Published private(set) var correct = 0
    @Published private(set) var total = 0
    @Published private(set) var streak = 0
    @Published private(set) var feedback: String?
    @Published private(set) var lastAnswerWasCorrect: Bool?
    /// True while a result is on screen and the next question is pending, so a
    /// fast tapper cannot answer the next note before seeing it.
    @Published private(set) var isShowingResult = false

    @Published var includeSharps = true { didSet { nextQuestion() } }
    @Published var includeFlats = true { didSet { nextQuestion() } }
    @Published var playAudio = true

    private let tone = TonePlayer()
    private weak var prefs: Preferences?
    private var pendingAdvance: DispatchWorkItem?

    var accuracy: String {
        guard total > 0 else { return "0%" }
        return "\(Int((Double(correct) / Double(total) * 100).rounded()))%"
    }

    /// What the person can tap. Drawn from the practice range so the drill and
    /// the trainer agree about what is being worked on.
    var answerChoices: [Note] { pool }

    private var pool: [Note] {
        let range = prefs?.range ?? Note.selectable
        var filtered = range
        if !includeSharps { filtered = filtered.filter { $0.accidental != .sharp } }
        if !includeFlats { filtered = filtered.filter { $0.accidental != .flat } }
        // Never leave the pool empty: filtering out both accidental kinds from a
        // range that happens to be all accidentals would otherwise deadlock the
        // drill with nothing to ask and nothing to tap.
        return filtered.isEmpty ? range : filtered
    }

    func bind(_ prefs: Preferences) {
        guard self.prefs == nil else { return }
        self.prefs = prefs
        nextQuestion(playSound: false)
    }

    func answer(_ note: Note) {
        guard !isShowingResult else { return }
        total += 1

        // Enharmonic answers count, same rule as the web version: anything that
        // sounds at the same pitch is the same note, however it is spelled.
        let isCorrect = note.frequency == question.frequency

        if isCorrect {
            correct += 1
            streak += 1
            lastAnswerWasCorrect = true
            feedback = streak > 1 ? "Correct, \(streak) streak" : "Correct"
            advance(after: 0.8)
        } else {
            streak = 0
            lastAnswerWasCorrect = false
            feedback = "Wrong, it was \(question.name) (\(question.fingering))"
            advance(after: 2.0)
        }
    }

    func skip() {
        guard !isShowingResult else { return }
        streak = 0
        lastAnswerWasCorrect = false
        feedback = "Skipped, it was \(question.name) (\(question.fingering))"
        advance(after: 1.5)
    }

    func reset() {
        correct = 0
        total = 0
        streak = 0
        feedback = nil
        lastAnswerWasCorrect = nil
        nextQuestion()
    }

    private func advance(after delay: Double) {
        isShowingResult = true
        pendingAdvance?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isShowingResult = false
            self?.feedback = nil
            self?.lastAnswerWasCorrect = nil
            self?.nextQuestion()
        }
        pendingAdvance = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func nextQuestion(playSound: Bool = true) {
        let choices = pool
        guard !choices.isEmpty else { return }
        var next = question
        if choices.count > 1 {
            // Never ask the same note twice running: a repeat reads as the drill
            // being stuck rather than as chance.
            while next.name == question.name {
                next = choices.randomElement() ?? question
            }
        } else {
            next = choices[0]
        }
        question = next

        if playSound && playAudio {
            tone.volume = prefs?.volume ?? 0.25
            tone.play(next, duration: 1.0)
        }
    }
}
