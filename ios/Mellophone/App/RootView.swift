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
        // Said once at launch and on every change, so a screenshot of a
        // broken layout can be matched to the size it was drawn at (#66).
        .onAppear { Self.logTextSize(typeSize) }
        .onChange(of: typeSize) { _, size in Self.logTextSize(size) }
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private static func logTextSize(_ size: DynamicTypeSize) {
        Log.ui.info("[TEXTSIZE] \(String(describing: size), privacy: .public) accessibility=\(size.isAccessibilitySize, privacy: .public)")
        #if DEBUG
        FileLog.write("[TEXTSIZE] \(size) accessibility=\(size.isAccessibilitySize)")
        #endif
    }
}

/// Standard page chrome: the dark background, the app's title block, and a
/// scrolling column of cards, under a strip that does not scroll and holds
/// the instrument (#36). Pinned, because the point of it is to be in the same
/// corner whatever is on the screen; on a strip of its own, because the
/// longest title here leaves no room beside it.
struct PageScaffold<Content: View>: View {
    // Resources, not Strings, so a literal at the call site is translated
    // (#67): a String passed to Text is shown as it is.
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?
    @ViewBuilder var content: () -> Content

    init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, @ViewBuilder content: @escaping () -> Content) {
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
                            .scaledFont(22, .bold)
                            .foregroundStyle(Theme.gold)
                        if let subtitle {
                            Text(subtitle)
                                .scaledFont(13)
                                .foregroundStyle(Theme.textDim)
                        }
                    }

                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    InstrumentChip()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Theme.bg)
            }
        }
    }
}

