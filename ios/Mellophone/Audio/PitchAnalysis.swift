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
    /// -40 dBFS, and measured, not chosen (#34). It was 0.005 until a real
    /// trumpet was tuned on a real phone: across that session the horn's
    /// readings ran from 0.011 to 0.446 with the middle one at 0.157, and
    /// every reading between 0.005 and 0.010 was the room's mains hum, 58 to
    /// 61 Hz, put on the screen as a note whenever nobody was playing. The
    /// detector is perfectly capable of finding a "pitch" in the hum of a
    /// fridge if it is asked to. A louder room will hum over this too; what
    /// stops a sound that is loud enough is `HeldPitch`, and a steady hum
    /// that loud is, to a tuner, a note.
    static let quietest = 0.010

    /// The lowest and highest sounds worth naming. A euphonium's bottom
    /// written F#3 sounds E2, 82 Hz, and a trumpet's top C6 sounds 932 Hz;
    /// this is most of an octave wider at each end so a wrong partial still
    /// gets named. The floor is under a euphonium's pedal Bb, 58 Hz, which is
    /// the note a student falls onto when the bottom of the horn gives way.
    ///
    /// It was 70 until the euphonium arrived (#25) and was measured before it
    /// moved: every semitone from that pedal up to G6 comes back within 3
    /// cents at both 44.1 and 48 kHz, and still does with everything under
    /// 300 Hz filtered off, which is what a phone's microphone does to a note
    /// this low. YIN measures how often the wave repeats, and a wave made of
    /// overtones alone still repeats at the fundamental.
    static let lowestHz = 50.0
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
        let end = Double(window.count - 1)
        guard start + length + Double(margin) < end else { return [] }
        // The NEWEST stretch that fits, a whole number of cycles on from the
        // first. The listener hands over twice what the pitch was measured
        // on, and drawing from the front of it would show the note as it was
        // a sixth of a second ago beside a needle that has already moved.
        while start + period + length + Double(margin) < end { start += period }

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

/// Whether what is coming in is a note being HELD, or only a sound that has a
/// pitch for a moment (#34).
///
/// A phone on a music stand hears everything: a new mail chime, a door, a
/// chair, somebody talking. The detector gives most of those a pitch, and it
/// is right to, they have one. Shown raw, the screen named the note of an
/// email arriving. Two things are true of a horn being held and of almost
/// nothing else in a room:
///
/// - It STAYS ON ONE NOTE. Speech and jingles move.
/// - It does NOT DIE AWAY. A chime is struck and falls from its first tenth
///   of a second; a blown note is as loud as the player blows it, for as long
///   as they do. This is the one that matters: the macOS Glass sound holds
///   392 Hz for six readings in a row, steadier than any student, while its
///   level goes 0.090, 0.031, 0.015, 0.011.
///
/// So a pitch is passed on only after `readingsNeeded` readings in a row on
/// the same note with none of them dying. Measured against the 20 alert and
/// mail sounds that ship with macOS, at the block size the phone hands over:
/// before this 15 of them put a pitch on the screen, Glass for six readings
/// running, and after it none is shown for more than two, which is short of
/// what the screen needs to count a note. `ios/README.md` has the numbers
/// and what still gets through.
///
/// Pure arithmetic on the two numbers a block gives, so it is tested without
/// a microphone. `PitchListener` keeps one and feeds it every block.
struct HeldPitch {

    /// Three readings, three tenths of a second. The screen's own count
    /// (`NoteConfirmation`) starts after this, and was shortened by the
    /// same amount, so a note is still confirmed six readings after it
    /// starts.
    static let readingsNeeded = 3

    /// Half a semitone either side of where the run sits. Nearer than this
    /// and it is the same note being held; further and it is another note.
    static let sameNoteCents = 50.0

    /// A reading under this fraction of the loudest of the last three is a
    /// sound on its way out: 6 dB in three tenths of a second or less. The
    /// horn in the same session never fell by more than a quarter between
    /// readings a whole second apart.
    static let dying = 0.5

    /// What became of the last reading, for the log and nothing else.
    enum Outcome: Equatable {
        case silence
        /// A pitch, not yet held for long enough to show.
        case waiting
        case held
        /// The run was thrown away because the pitch moved to another note.
        case moved
        /// The run was thrown away because the sound was dying away.
        case died
    }

    private(set) var outcome: Outcome = .silence
    /// How many readings the present run has in it.
    private(set) var length = 0

    /// The last three pitches of the run and how loud each was.
    private var pitches: [Double] = []
    private var levels: [Double] = []
    /// One reading that disagreed with a note already being held. See `take`.
    private var stray: (frequency: Double, level: Double)?

    /// Where the run sits: the middle of its last three pitches.
    ///
    /// The middle and not the newest, for the reason the listener always had:
    /// one block in a held note now and then comes back an octave out, and
    /// shown raw the needle slams to the wall and back.
    var pitch: Double? {
        pitches.isEmpty ? nil : pitches.sorted()[pitches.count / 2]
    }

    /// Takes one block's pitch and level. Returns the pitch to show, or nil
    /// while there is no held note.
    mutating func take(frequency: Double?, level: Double) -> Double? {
        guard let frequency, frequency > 0 else {
            self = HeldPitch()
            return nil
        }
        guard let centre = pitch else {
            begin(with: [(frequency, level)], as: .waiting)
            return nil
        }
        // Dying is asked first. A bell's pitch is perfectly steady on the way
        // down, so the other question would never catch it.
        if level < Self.dying * (levels.max() ?? 0) {
            begin(with: [(frequency, level)], as: .died)
            return nil
        }
        if abs(Pitch.cents(frequency, centre)) > Self.sameNoteCents {
            // A note that is already being held is allowed ONE reading
            // somewhere else, which is the octave error above, and keeps
            // its place. Two in a row and the player has moved: start again
            // from those two if they agree with each other, so a real change
            // of note costs three readings and not four.
            if length >= Self.readingsNeeded, stray == nil {
                stray = (frequency, level)
                outcome = .held
                return centre
            }
            if let earlier = stray, abs(Pitch.cents(frequency, earlier.frequency)) <= Self.sameNoteCents {
                begin(with: [earlier, (frequency, level)], as: .moved)
            } else {
                begin(with: [(frequency, level)], as: .moved)
            }
            return nil
        }
        stray = nil
        pitches.append(frequency)
        levels.append(level)
        if pitches.count > 3 {
            pitches.removeFirst()
            levels.removeFirst()
        }
        length += 1
        outcome = length >= Self.readingsNeeded ? .held : .waiting
        return outcome == .held ? pitch : nil
    }

    private mutating func begin(with readings: [(frequency: Double, level: Double)], as outcome: Outcome) {
        pitches = readings.map(\.frequency)
        levels = readings.map(\.level)
        length = readings.count
        stray = nil
        self.outcome = outcome
    }
}
