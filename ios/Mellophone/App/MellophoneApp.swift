import SwiftUI

@main
struct MellophoneApp: App {
    // One metronome for the whole app, owned here, so switching tabs never
    // interrupts the click. A student sets a tempo and then goes and looks at
    // the fingering chart while it runs; that has to keep working.
    @StateObject private var metronome = Metronome()
    @StateObject private var preferences = Preferences.shared

    init() {
        #if DEBUG
        FileLog.startNewRun()
        // What the RUNNING binary declares, not what the build product on the
        // mac says. Everything about background audio hangs off this key, and
        // it has been verified in the .app but never from inside the process.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        FileLog.write("[LAUNCH] UIBackgroundModes=\(modes.map { $0.joined(separator: ",") } ?? "MISSING")")
        FileLog.write("[LAUNCH] bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(metronome)
                .environmentObject(preferences)
                // Dark only. The web version is dark, band rooms are dim, and a
                // white screen on a music stand at a night game is hostile.
                .preferredColorScheme(.dark)
        }
    }
}
