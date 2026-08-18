import CoreHaptics
import OSLog
import UIKit

/// Downbeat haptic.
///
/// The point is playing loudly enough that you cannot hear a click: a thump you
/// feel through the case still tells you where beat one is. Everything here
/// degrades to silence rather than to an error, because a device without a
/// haptic engine (any iPad, the simulator) must not stop the metronome working.
///
/// Known limitation, recorded rather than hidden: the pulse fires from the UI
/// tick that reads the audio clock, not from the audio render thread. On a wired
/// or built-in output the offset is a frame or two and imperceptible. On
/// Bluetooth, where the audio itself is tens of milliseconds late, the haptic
/// leads the click by that latency. Fixing it properly means scheduling haptic
/// events ahead on the same timeline as the buffers, which is worth doing only
/// if it turns out to bother anyone in practice.
final class Haptics {
    private var engine: CHHapticEngine?
    private var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    func prepare() {
        guard isSupported else {
            Log.haptics.info("[HAPTICS] unsupported on this hardware, downbeat pulse disabled")
            return
        }
        guard engine == nil else {
            restartIfNeeded()
            return
        }
        do {
            let engine = try CHHapticEngine()
            // This app plays haptics ONLY, never audio through CoreHaptics.
            // Saying so matters: with the default (false) the haptic engine
            // joins the audio session and can disturb it, and this app's audio
            // session is load-bearing for background playback. Also cheaper.
            engine.playsHapticsOnly = true
            // The system stops the engine when the app backgrounds or on a media
            // services reset. Without these handlers the first pulse after that
            // silently does nothing forever.
            engine.stoppedHandler = { reason in
                Log.haptics.info("[HAPTICS] engine stopped reason=\(reason.rawValue, privacy: .public)")
            }
            engine.resetHandler = { [weak self] in
                Log.haptics.info("[HAPTICS] engine reset, restarting")
                try? self?.engine?.start()
            }
            try engine.start()
            self.engine = engine
            Log.haptics.info("[HAPTICS] engine ready")
        } catch {
            Log.haptics.error("[HAPTICS] engine start FAILED: \(error.localizedDescription, privacy: .public)")
            engine = nil
        }
    }

    private func restartIfNeeded() {
        guard let engine else { return }
        do { try engine.start() } catch {
            Log.haptics.error("[HAPTICS] restart FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A single sharp transient. Deliberately short and firm: this is a downbeat
    /// marker, not a notification buzz.
    func downbeat() {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            Log.haptics.error("[HAPTICS] downbeat FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        engine?.stop(completionHandler: nil)
    }
}
