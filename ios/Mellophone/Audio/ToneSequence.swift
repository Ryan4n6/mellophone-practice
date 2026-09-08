import AVFoundation

/// Lays a list of pitched events into one buffer at exact sample offsets.
///
/// This is the renderer `ScalePlayer` was built around, moved out so an
/// imported part can use it. The reason it exists at all is unchanged: the web
/// version fires a `setTimeout` per note, so every note inherits the timer's
/// jitter and the run wobbles. Rendering the whole thing into one buffer makes
/// the spacing a property of the buffer rather than of anything that has to be
/// woken up on time, so it cannot wobble at all.
///
/// What is new here is that onset and duration are PER EVENT. A scale is evenly
/// spaced and `ScalePlayer` still describes it that way; an imported part is
/// not, and it has rests in it.
enum ToneSequence {

    struct Event {
        let frequency: Double
        /// Seconds from the start of the buffer.
        let onset: Double
        let duration: Double
    }

    /// A part can be minutes long, and a buffer that size is not something to
    /// build in one piece. Callers rendering a whole score should cut it into
    /// chunks of a few bars and schedule them back to back with `at: nil`, the
    /// same discipline `Metronome` uses and for the same reason: never schedule
    /// against an absolute player timeline.
    static func render(events: [Event], volume: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        // Room for the last event to ring out fully rather than being cut off.
        // Taken over every event rather than off the last one, because events
        // are not required to arrive in onset order and a long note can start
        // before a short one that ends later.
        guard let totalDuration = events.map({ $0.onset + $0.duration }).max() else { return nil }
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)

        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let out = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) { out[i] = 0 }

        for event in events {
            guard event.duration > 0, event.frequency > 0 else { continue }
            guard let rendered = TonePlayer.render(
                frequency: event.frequency,
                duration: event.duration,
                volume: volume,
                format: format
            ), let source = rendered.floatChannelData?[0] else { continue }

            let offset = Int(event.onset * sampleRate)
            guard offset >= 0 else { continue }
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
