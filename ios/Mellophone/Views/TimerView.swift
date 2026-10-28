import SwiftUI

struct TimerView: View {
    @StateObject private var timer = PracticeTimer()
    @StateObject private var log = PracticeLog()
    @State private var tooShortNotice = false

    var body: some View {
        PageScaffold(title: "Practice Timer", subtitle: "Time it, then log it") {
            VStack(spacing: 18) {
                Text(formatDuration(timer.elapsed))
                    .scaledFont(56, .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(timer.isRunning ? Theme.gold : Theme.text)

                HStack(spacing: 10) {
                    Button { timer.toggle() } label: {
                        transportLabel(
                            timer.isRunning ? "Pause" : (timer.elapsed > 0 ? "Resume" : "Start"),
                            systemImage: timer.isRunning ? "pause.fill" : "play.fill",
                            prominent: true
                        )
                    }
                    .buttonStyle(.plain)

                    Button { timer.reset() } label: {
                        transportLabel("Reset", systemImage: "arrow.counterclockwise", prominent: false)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if log.save(seconds: timer.elapsed) {
                        timer.reset()
                        tooShortNotice = false
                    } else {
                        // The web version returns silently here, so a tap on
                        // Save after a couple of seconds looks like a broken
                        // button. Say what happened instead.
                        tooShortNotice = true
                    }
                } label: {
                    transportLabel("Save Session", systemImage: "square.and.arrow.down", prominent: false)
                }
                .buttonStyle(.plain)

                if tooShortNotice {
                    Text("Sessions under \(PracticeLog.minimumSeconds) seconds are not logged")
                        .scaledFont(12)
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                }
            }
            .card()

            logCard
        }
    }

    private func transportLabel(_ title: LocalizedStringResource, systemImage: String, prominent: Bool) -> some View {
        transportLabelRow(title, systemImage: systemImage, prominent: prominent).controlTextCap()
    }

    private func transportLabelRow(_ title: LocalizedStringResource, systemImage: String, prominent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .scaledFont(15, .bold)
        .foregroundStyle(prominent ? Color.black : Theme.text)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6).frame(minHeight: 50)
        .background(prominent ? Theme.gold : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice Log")
                .scaledFont(15, .bold)
                .foregroundStyle(Theme.text)

            if log.sessions.isEmpty {
                Text("No sessions logged yet.")
                    .scaledFont(13)
                    .foregroundStyle(Theme.textDim)
            } else {
                Text("\(log.sessions.count) sessions, \(formatDuration(log.totalSeconds)) total")
                    .scaledFont(13)
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)

                ForEach(log.sessions) { session in
                    HStack {
                        Text(session.date.formatted(date: .abbreviated, time: .omitted))
                            .scaledFont(13)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(formatDuration(session.seconds))
                            .scaledFont(13, .semibold)
                            .monospacedDigit()
                            .foregroundStyle(Theme.gold)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.cardBorder).frame(height: 1)
                    }
                }

                Button { log.clear() } label: {
                    Text("Clear Log")
                        .scaledFont(13, .semibold)
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6).frame(minHeight: 40)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .card()
    }
}
