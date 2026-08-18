import SwiftUI

/// The five tabs of the web version.
///
/// The web page also keeps the fingering chart permanently visible below every
/// panel. iOS gives five tab-bar slots before it collapses the rest into a
/// "More" list, so the chart lives at the bottom of the Trainer tab instead of
/// taking a sixth slot. Same content, same one-scroll-away access, no More menu.
struct RootView: View {
    @EnvironmentObject private var metronome: Metronome

    var body: some View {
        TabView {
            TrainerView()
                .tabItem { Label("Trainer", systemImage: "music.note") }

            ScalesView()
                .tabItem { Label("Scales", systemImage: "list.bullet") }

            DrillView()
                .tabItem { Label("Drill", systemImage: "target") }

            MetronomeView()
                .tabItem { Label("Metronome", systemImage: "metronome") }

            TimerView()
                .tabItem { Label("Timer", systemImage: "stopwatch") }
        }
        .tint(Theme.gold)
    }
}

/// Standard page chrome: the dark background, the app's title block, and a
/// scrolling column of cards.
struct PageScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.gold)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                    .padding(.top, 8)

                    content()
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
    }
}

/// Placeholder used by the tabs that land in later phases, so the shell is
/// navigable on device from phase 1 rather than crashing into an empty screen.
struct ComingSoonView: View {
    let title: String
    let issue: String

    var body: some View {
        PageScaffold(title: title) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not built yet")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Tracked in \(issue).")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
            }
            .card()
        }
    }
}

struct TrainerView: View {
    var body: some View { ComingSoonView(title: "Trainer", issue: "issue #4") }
}

struct ScalesView: View {
    var body: some View { ComingSoonView(title: "Scales", issue: "issue #5") }
}

struct DrillView: View {
    var body: some View { ComingSoonView(title: "Drill", issue: "issue #5") }
}

struct TimerView: View {
    var body: some View { ComingSoonView(title: "Timer", issue: "issue #6") }
}
