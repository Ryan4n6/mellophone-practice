import Foundation

/// What a stretch of microphone audio is: how loud, what pitch if any, and the
/// picture of it to draw.
///
/// Pure arithmetic on an array, split out of `PitchListener` so the part that
/// can be wrong about music is testable and the part that talks to the
/// microphone has nothing in it to be wrong about.
enum PitchAnalysis {

    struct Frame: Equatable {
        /// Nil when the window is too quiet or is not a note.
        let frequency: Double?
        /// RMS, 0 to 1.
        let level: Double
    }

    /// Below this the room is treated as silent and no pitch is looked for.
    ///
    /// About -46 dBFS. A horn at arm's length is forty decibels over it, and
    /// the detector is perfectly capable of finding a "pitch" in the hum of a
    /// fridge if it is asked to.
    static let quietest = 0.005

    /// The lowest and highest sounds worth naming. A mellophone's bottom
    /// written F#3 sounds 123 Hz and a trumpet's top C6 sounds 932 Hz; this is
    /// most of an octave wider at each end so a wrong partial still gets named.
    static let lowestHz = 70.0
    static let highestHz = 1500.0

    /// How sure the detector has to be. See `Pitch.fundamental(doubt:)`.
    static let doubt = 0.25

    static func frame(of window: [Double], sampleRate: Double) -> Frame {
        guard !window.isEmpty else { return Frame(frequency: nil, level: 0) }
        let level = (window.reduce(0) { $0 + $1 * $1 } / Double(window.count)).squareRoot()
        guard level >= quietest else { return Frame(frequency: nil, level: level) }
        let frequency = Pitch.fundamental(of: window, sampleRate: sampleRate,
                                          lowestHz: lowestHz, highestHz: highestHz, doubt: doubt)
        return Frame(frequency: frequency, level: level)
    }

    /// The sample at which the fundamental of `frequency` crosses zero going
    /// up, somewhere in the first period of `window`.
    ///
    /// The scope draws from here, every time, so that a steady note is a
    /// steady picture. Starting wherever the buffer happened to begin would
    /// redraw the same wave at a different place ten times a second.
    ///
    /// Found from the PHASE of the fundamental and not by looking for a zero
    /// crossing in the samples. A horn's wave crosses zero several times a
    /// cycle, a different several from one note to the next, and a trigger on
    /// the raw signal jumps between them.
    static func risingCrossing(of window: [Double], sampleRate: Double, frequency: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let period = sampleRate / frequency
        // A whole number of cycles, so the two sums are not biased by a
        // fraction of one left over at the end.
        let count = min(window.count, Int((Double(window.count) / period).rounded(.down) * period))
        guard count > 0 else { return 0 }
        var re = 0.0, im = 0.0
        for n in 0..<count {
            re += window[n] * cos(omega * Double(n))
            im += window[n] * sin(omega * Double(n))
        }
        // The fundamental is A cos(omega n - phi). That is a sine going up
        // through zero where omega n - phi = -pi / 2.
        let phi = atan2(im, re)
        var start = (phi - Double.pi / 2) / omega
        start = start.truncatingRemainder(dividingBy: period)
        if start < 0 { start += period }
        return start
    }

    /// How many of the target's cycles the scope shows.
    ///
    /// Six, because the picture has to show a note that is only a little out.
    /// At 33 cents flat each cycle is 2% too wide, which nobody can see in one
    /// cycle; across six the wave has slipped an eighth of a cycle behind by
    /// the right hand edge, and that is plain. More than six and a phone's
    /// width cannot draw the shape of each one.
    static let traceCycles = 6

    /// The wave to draw: `cycles` periods OF THE TARGET, starting where the
    /// heard note's fundamental goes up through zero, scaled to fill -1...1.
    ///
    /// The width is the target's and not the heard note's, on purpose. That is
    /// what makes the picture mean something: on pitch, the wave repeats
    /// exactly as often as the target drawn behind it. Flat, each cycle is
    /// wider than the target's and the wave falls behind it across the screen.
    /// Sharp, it runs ahead.
    ///
    /// The wave is SMOOTHED first, over half of its own period, twice. The raw
    /// signal was tried, through a real microphone, and it cannot be read: a
    /// brass tone is mostly overtones, and what came back was a scribble with
    /// thirty peaks in it laid over a sine with six. This picture has one job,
    /// to show whether the student's cycles are the same length as the
    /// note's, and the overtones say nothing about that. Averaging over half a
    /// period removes the even ones outright and leaves a twentieth of the
    /// third, so what is drawn is close to the fundamental alone: the
    /// student's own, at the student's own pitch, which is the one line that
    /// can be compared with the target's. The average is centred, so it moves
    /// nothing sideways.
    static func trace(of window: [Double], sampleRate: Double, heard: Double, target: Double,
                      cycles: Int = traceCycles, points: Int = 240) -> [Float] {
        guard heard > 0, target > 0, points > 1 else { return [] }
        let period = sampleRate / heard
        let half = max(1, Int((period / 4).rounded()))
        // Two passes each reach `half` samples either side, so the first
        // sample that has a full average behind it is 2 x half in.
        let margin = 2 * half + 1
        var start = risingCrossing(of: window, sampleRate: sampleRate, frequency: heard)
        while start < Double(margin) { start += period }
        let length = Double(cycles) * sampleRate / target
        guard start + length + Double(margin) < Double(window.count - 1) else { return [] }

        let smooth = boxcar(boxcar(window, half: half), half: half)

        var out = [Float](repeating: 0, count: points)
        var peak = 0.0
        for i in 0..<points {
            let position = start + length * Double(i) / Double(points - 1)
            let index = Int(position)
            let fraction = position - Double(index)
            let value = smooth[index] * (1 - fraction) + smooth[index + 1] * fraction
            out[i] = Float(value)
            peak = max(peak, abs(value))
        }
        guard peak > 0 else { return [] }
        return out.map { $0 / Float(peak) }
    }

    /// A centred moving average, `half` samples either side. The ends, where
    /// there is not a full span to average, are left at zero and never drawn.
    private static func boxcar(_ x: [Double], half: Int) -> [Double] {
        var out = [Double](repeating: 0, count: x.count)
        let span = 2 * half + 1
        guard x.count > span else { return out }
        var sum = x[0..<span].reduce(0, +)
        out[half] = sum / Double(span)
        for centre in (half + 1)..<(x.count - half) {
            sum += x[centre + half] - x[centre - half - 1]
            out[centre] = sum / Double(span)
        }
        return out
    }
}
