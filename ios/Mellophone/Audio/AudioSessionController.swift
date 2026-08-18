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
/// 3. **The click must layer over a play-along track.** `.mixWithOthers` means
///    starting the metronome does not kill whatever backing track is already
///    playing from another app. Without it, `.playback` interrupts other audio,
///    and a student running a play-along would have to choose between the track
///    and the click.
final class AudioSessionController {
    static let shared = AudioSessionController()

    /// Fired when the system takes the session away (phone call, Siri) and when
    /// it hands it back. `true` means "you were interrupted, stop"; `false`
    /// means "the interruption ended and the system says you may resume".
    var onInterruption: ((Bool) -> Void)?

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
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                isConfigured = true
                Log.audio.info("[AUDIO] category set: playback/default/mixWithOthers")
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
            Log.audio.info("[AUDIO] interruption began")
            onInterruption?(true)
        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            Log.audio.info("[AUDIO] interruption ended shouldResume=\(shouldResume, privacy: .public)")
            onInterruption?(false)
            _ = shouldResume
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
        if reason == .oldDeviceUnavailable {
            Log.audio.info("[AUDIO] output device removed, stopping playback")
            onRouteLoss?()
        }
    }
}
