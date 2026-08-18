import SwiftUI

@main
struct MellophoneApp: App {
    // One metronome for the whole app, owned here, so switching tabs never
    // interrupts the click. A student sets a tempo and then goes and looks at
    // the fingering chart while it runs; that has to keep working.
    @StateObject private var metronome = Metronome()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(metronome)
                // Dark only. The web version is dark, band rooms are dim, and a
                // white screen on a music stand at a night game is hostile.
                .preferredColorScheme(.dark)
        }
    }
}
