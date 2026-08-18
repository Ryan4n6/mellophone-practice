import AVFoundation
import OSLog

/// The one `AVAudioEngine` everything in the app shares.
///
/// This exists to prevent a specific bug rather than for tidiness. The metronome
/// and the tone player both need to make sound, and the obvious thing is to give
/// each its own engine. Two engines on one session do work, but starting the
/// second one can force the output route or sample rate to be reconfigured,
/// which posts `AVAudioEngineConfigurationChange` to the FIRST engine. The
/// metronome's handler for that is to stop and restart, so playing a note to
/// check your pitch would break the click.
///
/// That is exactly the combination a student uses: metronome running, tap a note
/// to hear where it should sit. One engine, and it cannot happen.
final class AudioEngineHost {
    static let shared = AudioEngineHost()

    let engine = AVAudioEngine()

    /// The format everything renders at. Follows the hardware, so it changes on
    /// a route change (48k built-in speaker to 44.1k over Bluetooth).
    private(set) var renderFormat: AVAudioFormat?

    /// Bumped whenever the render format changes, so clients know their cached
    /// buffers were rendered at a stale sample rate and have to be rebuilt.
    private(set) var formatGeneration = 0

    private init() {}

    /// Bring the engine up, reformatting if the hardware moved under us.
    /// Returns the format to render at.
    @discardableResult
    func start() throws -> AVAudioFormat {
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hardware.sampleRate > 0 ? hardware.sampleRate : 44_100

        if renderFormat?.sampleRate != sampleRate {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                throw AudioEngineError.formatUnavailable
            }
            renderFormat = format
            formatGeneration += 1
            Log.audio.info("[AUDIO] render format now \(sampleRate, privacy: .public) Hz, generation \(self.formatGeneration, privacy: .public)")
        }

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
            Log.audio.info("[AUDIO] engine started")
        }

        guard let renderFormat else { throw AudioEngineError.formatUnavailable }
        return renderFormat
    }

    /// Attach a player node and wire it to the main mixer at the render format.
    /// Safe to call again after a format change; the old connection is replaced.
    func connect(_ node: AVAudioPlayerNode, format: AVAudioFormat) {
        if node.engine == nil {
            engine.attach(node)
        } else {
            engine.disconnectNodeOutput(node)
        }
        // Mono into the mixer, which upmixes to whatever the route wants, so
        // nothing upstream has to know about channel counts.
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }
}

enum AudioEngineError: Error {
    case formatUnavailable
}
