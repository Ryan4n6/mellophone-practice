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
        static let instrument = "mello-instrument"
        static let partTempo = "mello-part-tempo"
        static let partCountIn = "mello-part-count-in"
        static let partRoom = "mello-part-room"
    }

    private let defaults = UserDefaults.standard

    /// Which horn the fingerings and concert keys are shown for.
    @Published var instrument: Instrument {
        didSet {
            defaults.set(instrument.rawValue, forKey: Key.instrument)
            // Here and not at the controls, of which there are now several
            // (#36). A log that says "flat by a fourth" is unreadable without
            // knowing which horn the app thought it was hearing.
            guard instrument != oldValue else { return }
            Log.store.info("[INSTRUMENT] now \(self.instrument.rawValue, privacy: .public), was \(oldValue.rawValue, privacy: .public)")
            #if DEBUG
            FileLog.write("[INSTRUMENT] now \(instrument.rawValue), was \(oldValue.rawValue)")
            #endif
        }
    }

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

    /// Beats per minute for an imported part that prints no tempo the reader
    /// can read.
    ///
    /// A chart that does print one opens at the page's tempo instead (#41),
    /// and the student's change to it is a share of the page kept on the
    /// chart's screen, not this. This is for the charts with nothing printed,
    /// one value for all of them: there is nothing per chart to remember but
    /// what the student last chose.
    @Published var partTempo: Int {
        didSet { defaults.set(partTempo, forKey: Key.partTempo) }
    }
    /// Whether a part starts with a bar of clicks.
    @Published var partCountIn: Bool {
        didSet { defaults.set(partCountIn, forKey: Key.partCountIn) }
    }
    /// The reverb a part plays through.
    @Published var partRoom: PartRoom {
        didSet { defaults.set(partRoom.rawValue, forKey: Key.partRoom) }
    }

    private init() {
        // Defaults are the WORKING range, not the instrument's full span. F#3 to
        // C6 is what is expected of a drum corps lead player; a high school
        // player lives around C4 to G5, and above the staff (G5 up) is
        // unreliable for anyone short of a strong college player. Widening it is
        // one tap away, and the fingering chart still shows everything.
        instrument = defaults.string(forKey: Key.instrument)
            .flatMap(Instrument.init(rawValue:)) ?? .mellophone
        rangeLow = defaults.string(forKey: Key.rangeLow) ?? "C4"
        rangeHigh = defaults.string(forKey: Key.rangeHigh) ?? "G5"
        // `double(forKey:)` returns 0 for a missing key, which would be silence.
        let storedVolume = defaults.object(forKey: Key.volume) as? Double
        volume = storedVolume ?? 0.25
        let storedSpeed = defaults.object(forKey: Key.scaleSpeed) as? Int
        scaleSpeed = storedSpeed ?? 500
        // 100 and not a march tempo: this is for learning a part, and a part
        // is learned under tempo first.
        let storedTempo = defaults.object(forKey: Key.partTempo) as? Int
        partTempo = min(220, max(40, storedTempo ?? 100))
        partCountIn = (defaults.object(forKey: Key.partCountIn) as? Bool) ?? true
        // A room by default. Dry is the honest signal and the worst first
        // impression, and nobody goes looking for a setting to fix a sound
        // they have already decided is bad.
        let storedRoom = defaults.string(forKey: Key.partRoom).flatMap(PartRoom.init(rawValue:))
        if storedRoom == nil, defaults.object(forKey: Key.partRoom) != nil {
            Log.store.error("[PREFS] stored part room is not one this build knows, using room")
        }
        partRoom = storedRoom ?? .room

        // A range saved by an older build could name a note that no longer
        // exists in the table. Fall back rather than hand every downstream
        // lookup a name it cannot resolve.
        // A range saved by an older build can name a note that no longer exists.
        // F3 is exactly that case: it shipped in the table before #9 removed it
        // for having no three-valve fingering, so anyone who used the old default
        // has "F3" on disk right now.
        if Note.named(rangeLow) == nil {
            Log.store.error("[STORE] saved low note \(self.rangeLow, privacy: .public) is unknown, resetting")
            rangeLow = "C4"
        }
        if Note.named(rangeHigh) == nil {
            Log.store.error("[STORE] saved high note \(self.rangeHigh, privacy: .public) is unknown, resetting")
            rangeHigh = "G5"
        }
    }

    /// The notes currently in the practice range.
    var range: [Note] { Note.range(from: rangeLow, to: rangeHigh) }
}
