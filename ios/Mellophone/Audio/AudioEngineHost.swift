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
            // The main mixer has to exist BEFORE the engine starts. It is made
            // the first time it is asked for, and asking for it only once the
            // engine is running does work for a player wired straight into it,
            // which is all this app did until the charts got a reverb. A chain
            // (player, effect, mixer) wired into a mixer that was made late
            // connects without complaint and then raises "player started when
            // in a disconnected state" on play. Reproduced outside the app on
            // a bare engine: every order of connecting failed, and only making
            // the mixer first, or restarting the engine, fixed it.
            _ = engine.mainMixerNode
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

    /// The same, with one effect between the player and the mixer.
    ///
    /// Mono into the effect and STEREO out of it. Apple's reverb will not
    /// initialise with one channel on its output (error -10868, format not
    /// supported), and the player has to stay mono because its buffers are.
    ///
    /// Both nodes are attached once and stay attached. Detaching a node from
    /// the running engine is what broke every later player once already, see
    /// `PartPlayer`, so a format change replaces the connections and nothing
    /// else.
    func connect(_ node: AVAudioPlayerNode, through effect: AVAudioUnit, format: AVAudioFormat) {
        for part in [node, effect] as [AVAudioNode] {
            if part.engine == nil {
                engine.attach(part)
            } else {
                engine.disconnectNodeOutput(part)
            }
        }
        let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2)
        engine.connect(effect, to: engine.mainMixerNode, format: stereo)
        engine.connect(node, to: effect, format: format)
    }
}

enum AudioEngineError: Error {
    case formatUnavailable
}
