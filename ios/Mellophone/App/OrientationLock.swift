import OSLog
import UIKit

/// Which way up the app may be (#43).
///
/// The whole app is portrait except the card view, which turns the phone on
/// its side because a lyre card is wider than it is tall: sideways, four lines
/// of the director's page come out at close to real card size, and upright
/// they are a third of it. The plist allows both so this can choose; the
/// delegate answers with whatever this says, which is portrait unless the card
/// view is up.
enum OrientationLock {
    @MainActor private(set) static var mask: UIInterfaceOrientationMask = .portrait

    @MainActor static func set(_ new: UIInterfaceOrientationMask, reason: String) {
        guard new != mask else { return }
        mask = new
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            // Every controller up the chain is asked again, the full screen
            // chart included, or the one on top keeps the old answer.
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: new)) { error in
                Log.score.error("[CARD] could not turn the screen for \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        let name = new == .portrait ? "portrait" : "landscape"
        Log.score.info("[CARD] screen now \(name, privacy: .public) (\(reason, privacy: .public))")
        #if DEBUG
        FileLog.write("[CARD] screen now \(name) (\(reason))")
        #endif
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.mask }
    }
}
