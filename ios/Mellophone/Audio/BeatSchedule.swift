import AVFoundation

/// The pure arithmetic behind the click, kept separate from the audio engine so
/// it can be tested without a device, a session, or a speaker.
///
/// This is where drift is won or lost. The naive implementation, and the one the
/// web version uses, advances a running cursor by one beat period at a time:
///
///     next = previous + period       // error accumulates, forever
///
/// Every rounding error in `period` is added to every beat that follows it. At
/// 44,100 Hz and 120 BPM the period is 22,050 samples exactly, so that looks
/// fine; at 137 BPM it is 19,313.868... samples, and truncating it loses about
/// 0.87 samples per beat, which is a full second of accumulated error after
/// roughly 50,000 beats. A musician feels the wander long before that.
///
/// So every beat is instead computed from a fixed anchor:
///
///     beat(i) = anchor + round(i * period)
///
/// The error against the ideal is never more than half a sample, no matter how
/// many beats have gone by, because nothing is ever added to a previous result.
struct BeatSchedule {
    /// Sample time, on the player node's own timeline, of beat offset 0.
    let anchorSample: AVAudioFramePosition
    /// The engine's render sample rate.
    let sampleRate: Double
    /// Beats per minute.
    let tempo: Double

    /// Seconds between beats.
    var period: Double { 60.0 / tempo }

    /// The exact sample at which beat `offset` should sound.
    ///
    /// `offset` is counted from the anchor, not from the start of the session,
    /// because the anchor is re-established whenever the tempo changes.
    func sampleTime(forOffset offset: Int) -> AVAudioFramePosition {
        anchorSample + AVAudioFramePosition((Double(offset) * period * sampleRate).rounded())
    }

    /// Where beat `offset` would land in a world with infinite precision. Used
    /// only by the tests and the drift instrumentation.
    func idealSample(forOffset offset: Int) -> Double {
        Double(anchorSample) + Double(offset) * period * sampleRate
    }

    /// Signed error, in samples, between what will actually be scheduled and the
    /// ideal. Bounded by 0.5 by construction for every offset.
    func error(forOffset offset: Int) -> Double {
        Double(sampleTime(forOffset: offset)) - idealSample(forOffset: offset)
    }

    /// The last beat offset whose sample time is at or before `sample`.
    /// Negative if the anchor has not been reached yet.
    ///
    /// This has to agree with `sampleTime(forOffset:)` EXACTLY, not
    /// approximately. The obvious one-liner,
    /// `floor(elapsed / (period * sampleRate))`, works from the ideal beat
    /// position, while `sampleTime(forOffset:)` rounds, so the two disagree by
    /// one beat at any boundary where the rounding went down. Roughly half of
    /// all beats, in practice.
    ///
    /// On the beat dots that would be a sub-sample display error and would not
    /// matter. It matters because `Metronome.reanchorIfRunning` uses this to
    /// carry the beat-in-measure across a tempo change: one off-by-one there
    /// moves the DOWNBEAT, which is audible and wrong. Caught by
    /// `testOffsetLookupAgreesWithScheduledTimes` before it ever ran on a horn.
    ///
    /// So: take the ideal answer as a starting guess, then reconcile it against
    /// the real, rounded sample times. The correction is never more than one
    /// step in either direction.
    func offset(atOrBefore sample: AVAudioFramePosition) -> Int {
        let elapsed = Double(sample - anchorSample)
        var candidate = Int(floor(elapsed / (period * sampleRate)))
        while sampleTime(forOffset: candidate + 1) <= sample { candidate += 1 }
        while sampleTime(forOffset: candidate) > sample { candidate -= 1 }
        return candidate
    }
}

extension BeatSchedule {
    /// Length in samples of the buffer representing beat `offset`, such that
    /// laying the buffers END TO END puts every beat exactly where
    /// `sampleTime(forOffset:)` says it belongs.
    ///
    /// This is the same arithmetic viewed differently, and it is what lets the
    /// metronome schedule buffers back to back instead of at absolute times on
    /// the player's timeline. Because
    ///
    ///     sum of lengths 0..<n  ==  round(n * period)  ==  sampleTime(n)
    ///
    /// concatenation is exact for ever, with the same sub-half-sample bound. The
    /// lengths alternate between two adjacent integers to absorb the fraction,
    /// which is the same trick a line-drawing algorithm uses.
    func bufferLength(forOffset offset: Int) -> Int {
        Int(sampleTime(forOffset: offset + 1) - sampleTime(forOffset: offset))
    }

    /// The two lengths `bufferLength(forOffset:)` can ever return, so the
    /// buffers can be built once per tempo rather than once per beat.
    var bufferLengthOptions: (short: Int, long: Int) {
        let exact = period * sampleRate
        let short = Int(exact.rounded(.down))
        return (short, short + 1)
    }
}
