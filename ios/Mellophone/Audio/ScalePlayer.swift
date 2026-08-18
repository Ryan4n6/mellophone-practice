import AVFoundation
import Combine
import OSLog

/// Plays a scale, evenly.
///
/// The web version fires a `setTimeout` per note, so every note inherits the
/// timer's jitter and the run wobbles. Here the WHOLE SCALE is rendered into one
/// buffer with each note placed at an exact sample offset, and that buffer is
/// handed to the player in a single call. The spacing is then a property of the
/// buffer rather than of anything that has to be woken up on time, so it cannot
/// wobble at all.
///
/// A thirteen-note chromatic at the slowest speed is about ten seconds of audio,
/// which is a few hundred thousand samples. Rendering it costs less than the
/// gap between two notes.
final class ScalePlayer: ObservableObject {
    /// Index of the note currently sounding, or nil when stopped.
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false

    private let player = AVAudioPlayerNode()
    private var formatGeneration = -1

    /// Seconds between note onsets, so the UI can map the audio clock back to an
    /// index without knowing how the buffer was built.
    private var interval: Double = 0.5
    private var noteCount = 0
    private var startSample: AVAudioFramePosition = 0
    private var sampleRate: Double = 48_000
    private var uiTimer: Timer?

    func play(_ scale: Scale, millisecondsPerNote: Int, volume: Double) {
        stop()

        guard AudioSessionController.shared.activate() else {
            Log.tone.error("[SCALE] play ABORTED: audio session would not activate")
            return
        }

        do {
            let format = try AudioEngineHost.shared.start()
            if formatGeneration != AudioEngineHost.shared.formatGeneration {
                formatGeneration = AudioEngineHost.shared.formatGeneration
                AudioEngineHost.shared.connect(player, format: format)
            }

            let notes = scale.notes
            guard !notes.isEmpty else { return }

            interval = Double(millisecondsPerNote) / 1000
            noteCount = notes.count
            sampleRate = format.sampleRate

            guard let buffer = Self.render(
                notes: notes,
                interval: interval,
                volume: volume,
                format: format
            ) else {
                Log.tone.error("[SCALE] play ABORTED: could not render buffer")
                return
            }

            player.play()
            guard
                let nodeTime = player.lastRenderTime,
                let playerTime = player.playerTime(forNodeTime: nodeTime)
            else {
                // No clock yet means no way to drive the highlight. The scale
                // would still SOUND correct, but a run with no moving highlight
                // looks broken, so treat it as a failure rather than half work.
                Log.tone.error("[SCALE] play ABORTED: no render clock yet")
                player.stop()
                return
            }
            startSample = playerTime.sampleTime

            // This handler also fires when stop() flushes the buffer, so
            // finish() has to be safe to run after an explicit stop. It is:
            // both just clear the same state.
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                DispatchQueue.main.async { self?.finish() }
            }

            isPlaying = true
            currentIndex = 0
            startUITimer()
            Log.tone.info("[SCALE] playing \(scale.name, privacy: .public), \(notes.count, privacy: .public) notes at \(millisecondsPerNote, privacy: .public) ms")
        } catch {
            Log.tone.error("[SCALE] play FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        uiTimer?.invalidate()
        uiTimer = nil
        player.stop()
        isPlaying = false
        currentIndex = nil
    }

    private func finish() {
        uiTimer?.invalidate()
        uiTimer = nil
        isPlaying = false
        currentIndex = nil
        Log.tone.debug("[SCALE] finished")
    }

    /// Drives the highlight off the audio clock, for the same reason the
    /// metronome's dots are: a separate UI timer would drift against the sound
    /// it is supposed to be pointing at.
    private func startUITimer() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard
                let self,
                let nodeTime = self.player.lastRenderTime,
                let playerTime = self.player.playerTime(forNodeTime: nodeTime)
            else { return }
            let elapsed = Double(playerTime.sampleTime - self.startSample) / self.sampleRate
            let index = Int(elapsed / self.interval)
            guard index >= 0, index < self.noteCount else { return }
            if self.currentIndex != index { self.currentIndex = index }
        }
        RunLoop.main.add(timer, forMode: .common)
        uiTimer = timer
    }

    /// Lay every note into one buffer at its exact sample offset.
    ///
    /// Each note sounds for 90% of the gap to the next one, matching the web
    /// version, so the notes are separated rather than slurred together.
    static func render(notes: [Note], interval: Double, volume: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let noteDuration = interval * 0.9
        // Room for the last note to ring out fully rather than being cut off.
        let totalDuration = interval * Double(notes.count - 1) + noteDuration
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)

        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let out = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) { out[i] = 0 }

        for (index, note) in notes.enumerated() {
            guard let rendered = TonePlayer.render(
                frequency: note.frequency,
                duration: noteDuration,
                volume: volume,
                format: format
            ), let source = rendered.floatChannelData?[0] else { continue }

            let offset = Int(Double(index) * interval * sampleRate)
            for i in 0..<Int(rendered.frameLength) {
                let target = offset + i
                guard target < Int(frameCount) else { break }
                // Sum rather than overwrite: at the fastest speed a note's
                // release can still be sounding when the next one starts, and
                // overwriting would chop it off mid-decay.
                out[target] += source[i]
            }
        }

        // Summing overlapping releases can push past full scale, so scale the
        // whole buffer back if it did. Clipping a scale run is far more audible
        // than it being slightly quieter.
        var peak: Float = 0
        for i in 0..<Int(frameCount) { peak = max(peak, abs(out[i])) }
        if peak > 1 {
            let gain = 1 / peak
            for i in 0..<Int(frameCount) { out[i] *= gain }
        }

        return buffer
    }
}
