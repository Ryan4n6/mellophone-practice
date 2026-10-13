import AVFoundation
import Accelerate

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
        /// A scale leaves this alone. A part says which notes run together.
        var articulation = Articulation.separate
        /// Zero for a scale, which is the tone as it always was. A part at
        /// sounding pitch holds the filter open; see `TonePlayer.render`.
        var brightnessFloor = 0.0
    }

    /// A part can be minutes long, and a buffer that size is not something to
    /// build in one piece. Callers rendering a whole score should cut it into
    /// chunks of a few bars and schedule them back to back with `at: nil`, the
    /// same discipline `Metronome` uses and for the same reason: never schedule
    /// against an absolute player timeline.
    ///
    /// `frames` is how a caller does that. Given, the buffer is EXACTLY that
    /// long: silence where nothing sounds, including a buffer with no events in
    /// it at all, because a bar of rest still has to take a bar of time. Back
    /// to back buffers are placed by their length, so a chunk that came out
    /// short by a note's release would pull every later bar early.
    static func render(events: [Event], volume: Double, format: AVAudioFormat,
                       frames: AVAudioFrameCount? = nil) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount: AVAudioFrameCount
        if let frames {
            frameCount = frames
        } else {
            // Room for the last event to ring out fully rather than being cut
            // off. Taken over every event rather than off the last one, because
            // events are not required to arrive in onset order and a long note
            // can start before a short one that ends later.
            guard let totalDuration = events.map({ $0.onset + $0.duration }).max() else { return nil }
            frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        }

        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let out = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        // vDSP for the four passes over the buffer, here and below. They were
        // plain loops, which is nothing in a release build and a real wait in
        // a debug one, and a debug build is what gets installed on a phone to
        // try something. Readying the first bars of a real chart took about
        // 1.5 s in the simulator; with these on vDSP it was about 0.9 s, and
        // with the wavetable build in TonePlayer vectorised too, about 0.35 s.
        // Same arithmetic, same samples out.
        vDSP_vclr(out, 1, vDSP_Length(frameCount))

        for event in events {
            guard event.duration > 0, event.frequency > 0 else { continue }
            guard let rendered = TonePlayer.render(
                frequency: event.frequency,
                duration: event.duration,
                volume: volume,
                format: format,
                articulation: event.articulation,
                brightnessFloor: event.brightnessFloor
            ), let source = rendered.floatChannelData?[0] else { continue }

            let offset = Int(event.onset * sampleRate)
            guard offset >= 0 else { continue }
            // Cut at the end of the buffer rather than running past it.
            let count = min(Int(rendered.frameLength), Int(frameCount) - offset)
            guard count > 0 else { continue }
            // Sum rather than overwrite: at the fastest speed a note's release
            // can still be sounding when the next one starts, and overwriting
            // would chop it off mid-decay.
            vDSP_vadd(source, 1, out + offset, 1, out + offset, 1, vDSP_Length(count))
        }

        // Summing overlapping releases can push past full scale, so scale the
        // whole buffer back if it did. Clipping a scale run is far more audible
        // than it being slightly quieter.
        var peak: Float = 0
        vDSP_maxmgv(out, 1, &peak, vDSP_Length(frameCount))
        if peak > 1 {
            var gain = 1 / peak
            vDSP_vsmul(out, 1, &gain, out, 1, vDSP_Length(frameCount))
        }

        return buffer
    }
}
