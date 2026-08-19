import AVFoundation
import OSLog

/// Owns the one `AVAudioSession` the whole app shares.
///
/// Three requirements drive every choice here, and all three come from what
/// practising actually looks like rather than from what is easy:
///
/// 1. **The click must sound with the ringer switch off.** Category `.playback`
///    is the only category that ignores the silent switch. `.ambient` and
///    `.soloAmbient` both go quiet, which would make the app useless in exactly
///    the situation it exists for.
/// 2. **The click must survive a locked screen.** `.playback` plus the `audio`
///    background mode in Info.plist keeps the engine rendering when the phone is
///    face down on a stand or in a pocket.
/// 3. **Nothing else may be added to the category options.** In particular NOT
///    `.mixWithOthers`, however tempting it is.
///
/// The third point was learned the hard way. `.mixWithOthers` was set so the
/// click could layer over a play-along track from another app. It also declares
/// this app's audio as SECONDARY, and secondary audio does not earn background
/// rendering, so it silently breaks requirement 2.
///
/// Measured on an iPhone 16 Pro, background mode present, session active,
/// launched from the home screen with nothing attached:
///
///     BG audio=14.847s wall=14.852s   locked, still rendering
///     BG audio=15.529s wall=19.853s   audio clock FROZE
///     BG audio=15.529s wall=29.853s   still frozen
///     BG audio=34.836s wall=34.851s   screen on, catches up
///
/// The app was never suspended: its timers kept firing and `engine.isRunning`
/// stayed true throughout. iOS simply stopped RENDERING, and the engine has no
/// way to tell you that happened.
///
/// The cost is real: starting the metronome now interrupts whatever else is
/// playing. That is the correct trade. A metronome that dies when the phone
/// goes in a pocket is not a metronome. `.duckOthers` was rejected too, because
/// the click never stops and a backing track would be permanently ducked.
final class AudioSessionController {
    static let shared = AudioSessionController()

    /// Fired when the system takes the session away (phone call, Siri).
    var onInterruption: ((Bool) -> Void)?

    /// Fired when an interruption ends. The flag is the system's
    /// `.shouldResume` hint.
    ///
    /// This used to be folded into `onInterruption` with a `false`, and the one
    /// listener ignored it, so ANY interruption stopped the metronome
    /// permanently. Nothing ever started it again. Split out so resuming is a
    /// separate, deliberate decision rather than a parameter nobody read.
    var onInterruptionEnded: ((Bool) -> Void)?

    /// Fired when the audio route changes in a way that should stop playback,
    /// i.e. headphones were pulled out. iOS convention is that yanking the cable
    /// pauses, it does not blast the click out of the speaker.
    var onRouteLoss: (() -> Void)?

    private var isConfigured = false

    private init() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    /// Configure and activate. Safe to call repeatedly; the category is only set
    /// once, but activation is re-asserted because the system deactivates the
    /// session after an interruption and the caller is the one who knows it
    /// wants to make noise again.
    @discardableResult
    func activate() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if !isConfigured {
                try session.setCategory(.playback, mode: .default, options: [])
                isConfigured = true
                Log.audio.info("[AUDIO] category set: playback/default, no options")
            }
            try session.setActive(true)
            Log.audio.info(
                "[AUDIO] session active sampleRate=\(session.sampleRate, privacy: .public) outputLatency=\(session.outputLatency, privacy: .public)s route=\(session.currentRoute.outputs.first?.portType.rawValue ?? "none", privacy: .public)"
            )
            return true
        } catch {
            // Not fatal: the UI stays usable, the click just will not sound. Log
            // loudly because a silent metronome with no explanation is the worst
            // possible failure for this app.
            Log.audio.error("[AUDIO] activation FAILED: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            // AVAudioSessionInterruptionWasSuspendedKey was deprecated in iOS
            // 14.5 in favour of the reason key, which says more anyway: it
            // distinguishes a phone call from the app being suspended from the
            // built-in mic being taken.
            let reason = (info[AVAudioSessionInterruptionReasonKey] as? UInt).map(String.init) ?? "unknown"
            Log.audio.info("[AUDIO] interruption began reason=\(reason, privacy: .public)")
            #if DEBUG
            FileLog.write("[AUDIO] INTERRUPTION BEGAN reason=\(reason)")
            #endif
            onInterruption?(true)
        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            Log.audio.info("[AUDIO] interruption ended shouldResume=\(shouldResume, privacy: .public)")
            #if DEBUG
            FileLog.write("[AUDIO] INTERRUPTION ENDED shouldResume=\(shouldResume)")
            #endif
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }

        Log.audio.info("[AUDIO] route change reason=\(reason.rawValue, privacy: .public)")
        #if DEBUG
        let route = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "none"
        FileLog.write("[AUDIO] ROUTE CHANGE reason=\(reason.rawValue) route=\(route)")
        #endif
        if reason == .oldDeviceUnavailable {
            Log.audio.info("[AUDIO] output device removed, stopping playback")
            onRouteLoss?()
        }
    }
}
