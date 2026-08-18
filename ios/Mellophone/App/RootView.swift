import SwiftUI

/// The five tabs of the web version.
///
/// The web page also keeps the fingering chart permanently visible below every
/// panel. iOS gives five tab-bar slots before it collapses the rest into a
/// "More" list, so the chart lives at the bottom of the Trainer tab instead of
/// taking a sixth slot. Same content, same one-scroll-away access, no More menu.
struct RootView: View {
    @EnvironmentObject private var metronome: Metronome
    @State private var selection: Tab = RootView.initialTab

    enum Tab: Hashable { case trainer, scales, drill, metronome, timer }

    /// DEBUG only: lets a screenshot of any tab be taken without tapping.
    ///
    ///     xcrun simctl launch booted com.massfeller.mellophone -startTab drill
    ///
    /// Arguments of the form -key value land in UserDefaults, so this needs no
    /// argument parsing. Ships as .trainer in release builds regardless.
    static var initialTab: Tab {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "startTab") {
        case "scales": return .scales
        case "drill": return .drill
        case "metronome": return .metronome
        case "timer": return .timer
        default: return .trainer
        }
        #else
        return .trainer
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            TrainerView()
                .tabItem { Label("Trainer", systemImage: "music.note") }
                .tag(Tab.trainer)

            ScalesView()
                .tabItem { Label("Scales", systemImage: "list.bullet") }
                .tag(Tab.scales)

            DrillView()
                .tabItem { Label("Drill", systemImage: "target") }
                .tag(Tab.drill)

            MetronomeView()
                .tabItem { Label("Metronome", systemImage: "metronome") }
                .tag(Tab.metronome)

            TimerView()
                .tabItem { Label("Timer", systemImage: "stopwatch") }
                .tag(Tab.timer)
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

