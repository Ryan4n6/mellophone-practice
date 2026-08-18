import Foundation
import OSLog

/// Everything the app remembers, on the device and nowhere else.
///
/// Keys keep the web version's `mello-` prefix. They are not shared with
/// anything, they never leave the phone, and there is no backend to send them
/// to; see PrivacyInfo.xcprivacy and issue #2.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let rangeLow = "mello-range-low"
        static let rangeHigh = "mello-range-high"
        static let scaleSpeed = "mello-scale-speed"
        static let volume = "mello-volume"
        static let practiceLog = "mello-practice-log"
    }

    private let defaults = UserDefaults.standard

    @Published var rangeLow: String {
        didSet { defaults.set(rangeLow, forKey: Key.rangeLow) }
    }
    @Published var rangeHigh: String {
        didSet { defaults.set(rangeHigh, forKey: Key.rangeHigh) }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: Key.volume) }
    }
    /// Milliseconds per note during scale playback.
    ///
    /// The web version writes this in `saveScaleSpeed` and never reads it back
    /// on load, so the setting silently does not persist. Ported as a working
    /// preference rather than a faithful bug.
    @Published var scaleSpeed: Int {
        didSet { defaults.set(scaleSpeed, forKey: Key.scaleSpeed) }
    }

    private init() {
        rangeLow = defaults.string(forKey: Key.rangeLow) ?? "F3"
        rangeHigh = defaults.string(forKey: Key.rangeHigh) ?? "C6"
        // `double(forKey:)` returns 0 for a missing key, which would be silence.
        let storedVolume = defaults.object(forKey: Key.volume) as? Double
        volume = storedVolume ?? 0.25
        let storedSpeed = defaults.object(forKey: Key.scaleSpeed) as? Int
        scaleSpeed = storedSpeed ?? 500

        // A range saved by an older build could name a note that no longer
        // exists in the table. Fall back rather than hand every downstream
        // lookup a name it cannot resolve.
        if Note.named(rangeLow) == nil {
            Log.store.error("[STORE] saved low note \(self.rangeLow, privacy: .public) is unknown, resetting")
            rangeLow = "F3"
        }
        if Note.named(rangeHigh) == nil {
            Log.store.error("[STORE] saved high note \(self.rangeHigh, privacy: .public) is unknown, resetting")
            rangeHigh = "C6"
        }
    }

    /// The notes currently in the practice range.
    var range: [Note] { Note.range(from: rangeLow, to: rangeHigh) }
}
