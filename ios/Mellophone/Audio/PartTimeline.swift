import Foundation

/// Which line of a part to play.
///
/// A horn part written divisi puts two noteheads on one stem, and the reader
/// numbers them from the top: voice 0 is the highest. A student plays ONE of
/// those lines, so the default is a single line and `all` is there for hearing
/// how the two fit together.
enum PartVoice: Hashable {
    case line(Int)
    case all
}

/// What gets the beat, which is what a tempo number counts.
///
/// "120" on a chart means 120 of something, and the something depends on the
/// time signature: a quarter in 4/4, a half in 2/2, a DOTTED quarter in 6/8.
/// The last one is why this is not just the bottom number. A 6/8 march marked
/// 120 is felt in two, and counting its eighths instead would make the app's
/// 120 a third of the director's.
struct Pulse: Equatable {
    /// Length in quarter notes.
    let quarters: Double
    let name: String

    static func of(_ signature: (beats: Int, unit: Int)) -> Pulse {
        switch signature.unit {
        case 2: return Pulse(quarters: 2, name: "half note")
        case 8 where signature.beats >= 6 && signature.beats % 3 == 0:
            return Pulse(quarters: 1.5, name: "dotted quarter")
        case 8: return Pulse(quarters: 0.5, name: "eighth note")
        case 16: return Pulse(quarters: 0.25, name: "sixteenth note")
        default: return Pulse(quarters: 1, name: "quarter note")
        }
    }
}

/// A score laid out in seconds: one line of it, one range of bars, one tempo.
///
/// Everything here is arithmetic on values, with no audio and no clock in it,
/// so the whole question of "what sounds when" is answerable in a test. The
/// player only has to render what this says and put the buffers end to end.
struct PartTimeline {

    struct Entry: Identifiable {
        let event: ScoreEvent
        /// Which moment in the part this belongs to. Every notehead of a
        /// divisi chord shares one, so the highlight can light them together.
        let slot: Int
        /// Seconds from the start of the RANGE, not of the score.
        let start: Double
        /// Seconds, as written. What actually sounds is a little shorter; see
        /// `sounding(_:)`.
        let duration: Double
        /// Nil for a rest and for nothing else. A pitch outside the horn's
        /// range has no row in the note table but still has a frequency here.
        let frequency: Double?

        var id: UUID { event.id }
    }

    struct Measure: Equatable {
        let number: Int
        let start: Double
    }

    /// A few bars, positioned by sample so that chunks laid end to end cannot
    /// drift against the timeline they were cut from.
    struct Chunk {
        let startFrame: Int
        let frames: Int
        let events: [ToneSequence.Event]
    }

    let entries: [Entry]
    let measures: [Measure]
    /// Seconds from the first bar of the range to the end of its last.
    let duration: Double
    let pulse: Pulse
    let secondsPerPulse: Double
    /// One bar of the opening time signature, counted in pulses.
    let countInBeats: Int

    private let slotStarts: [Double]

    init(score: Score, voice: PartVoice, measures range: ClosedRange<Int>, bpm: Double) {
        let pulse = Pulse.of(score.timeSignature)
        let secondsPerQuarter = 60 / (max(bpm, 1) * pulse.quarters)
        self.pulse = pulse
        self.secondsPerPulse = secondsPerQuarter * pulse.quarters

        let openingQuarters = Double(score.timeSignature.beats) * 4 / Double(score.timeSignature.unit)
        self.countInBeats = min(12, max(2, Int((openingQuarters / pulse.quarters).rounded())))

        // A slot is one moment in the part. The reader emits a chord's heads
        // one after another, highest first, all with the same onset, so voice 0
        // opens a slot and anything else joins the one before it.
        var slots: [[ScoreEvent]] = []
        for event in score.events {
            if event.voice == 0 || slots.isEmpty {
                slots.append([event])
            } else {
                slots[slots.count - 1].append(event)
            }
        }

        var entries: [Entry] = []
        var measures: [Measure] = []
        var slotStarts: [Double] = []
        var quarters = 0.0
        var origin: Double?
        var end = 0.0

        for (index, slot) in slots.enumerated() {
            let lead = slot[0]
            // Beats are counted in the measure's OWN unit, so they are turned
            // into quarter notes here, bar by bar. Converting the whole part
            // with one factor plays a 6/8 section of a 4/4 chart at half speed.
            let toQuarters = 4 / Double(score.beatUnit(of: lead.measure))
            // How far the part moves on is the gap to the next slot, which the
            // reader set from the longest head. Only the last slot has to fall
            // back on its own length.
            let advanceBeats = index + 1 < slots.count
                ? slots[index + 1][0].onsetBeats - lead.onsetBeats
                : (slot.map(\.durationBeats).max() ?? 0)
            let advance = max(0, advanceBeats) * toQuarters
            defer { quarters += advance }

            guard range.contains(lead.measure) else { continue }
            let zero = origin ?? quarters
            origin = zero
            let start = (quarters - zero) * secondsPerQuarter
            end = (quarters + advance - zero) * secondsPerQuarter

            if measures.last?.number != lead.measure {
                measures.append(Measure(number: lead.measure, start: start))
            }

            let chosen: [ScoreEvent]
            switch voice {
            case .all:
                chosen = slot
            case .line(let line):
                // Where the part is in unison there is one head, and both lines
                // play it. Taking the lowest head when the asked-for line is
                // missing is what keeps the bottom part from going silent
                // every time the two parts meet.
                chosen = [slot.first { $0.voice == line } ?? slot[slot.count - 1]]
            }
            let slotIndex = slotStarts.count
            slotStarts.append(start)
            for event in chosen {
                entries.append(Entry(event: event,
                                     slot: slotIndex,
                                     start: start,
                                     duration: event.durationBeats * toQuarters * secondsPerQuarter,
                                     frequency: Self.frequency(of: event)))
            }
        }

        self.entries = entries
        self.measures = measures
        self.slotStarts = slotStarts
        self.duration = end
    }

    /// What an event sounds at, or nil for a rest.
    ///
    /// The out of range case is the reason this is not just `note?.frequency`.
    /// A pitch above C6 has no row in the note table, so `note` is nil, and
    /// reading that as silence would drop exactly the bars a student most needs
    /// to hear. The name is still a pitch, and the table is in equal
    /// temperament (`ScalePitchTests` holds it to that), so the frequency is
    /// worked out the same way the table's were.
    static func frequency(of event: ScoreEvent) -> Double? {
        if let note = event.note { return note.frequency }
        guard let name = event.outOfRangeName,
              let midi = Fingering.semitoneValue(of: name) else { return nil }
        return 440 * pow(2, Double(midi - 69) / 12)
    }

    /// How long a note actually sounds.
    ///
    /// A hair less than written, so two notes on the same pitch are two notes
    /// and not one long one. The gap is capped because a tenth of a whole note
    /// at a slow tempo is a hole you can hear, and a brass player would not
    /// leave it.
    static func sounding(_ duration: Double) -> Double {
        duration - min(duration * 0.1, 0.04)
    }

    /// The slot sounding at `seconds` into the range, or nil outside it.
    func slot(at seconds: Double) -> Int? {
        guard seconds >= 0, seconds < duration, !slotStarts.isEmpty else { return nil }
        var low = 0, high = slotStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if slotStarts[middle] <= seconds { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// The bar sounding at `seconds` into the range.
    func measure(at seconds: Double) -> Int? {
        measures.last { $0.start <= seconds }?.number
    }

    /// Which beat of its bar is sounding at `seconds`, counted from 1.
    ///
    /// Counted from the bar line and not from the start of the range, so a bar
    /// of 2/4 dropped into a 4/4 chart does not leave every count after it two
    /// beats out. The beat is the chart's opening pulse throughout, which is
    /// also what the count-in clicks.
    func beat(at seconds: Double) -> Int? {
        guard seconds >= 0, seconds < duration,
              let bar = measures.last(where: { $0.start <= seconds }) else { return nil }
        // The nudge is for a time that lands exactly on a beat. At 72 the third
        // beat of bar 2 divides out to 1.9999999999999998, and without the
        // nudge it would still read as the second beat for one tick.
        return Int((seconds - bar.start) / secondsPerPulse + 1e-6) + 1
    }

    /// Cut the range into pieces of at least `minimumSeconds`, on bar lines.
    ///
    /// A four page chart at a slow tempo is ten minutes of audio, which is over
    /// a hundred megabytes as one buffer. A few bars at a time is a few hundred
    /// kilobytes and is ready before the bar in front of it has finished.
    ///
    /// Every boundary is rounded from its own position in SECONDS, never added
    /// up from the lengths before it, which is `BeatSchedule`'s rule: a sum of
    /// rounded lengths wanders, a rounded position cannot.
    func chunks(sampleRate: Double, minimumSeconds: Double = 3) -> [Chunk] {
        guard duration > 0, !measures.isEmpty else { return [] }
        func frame(_ seconds: Double) -> Int { Int((seconds * sampleRate).rounded()) }

        let boundaries = measures.map(\.start) + [duration]
        var chunks: [Chunk] = []
        var opened = 0
        for index in 1..<boundaries.count {
            let isLast = index == boundaries.count - 1
            guard boundaries[index] - boundaries[opened] >= minimumSeconds || isLast else { continue }
            let from = boundaries[opened], to = boundaries[index]
            opened = index
            let frames = frame(to) - frame(from)
            guard frames > 0 else { continue }

            // Half a sample of slack on each edge, so a note that starts
            // exactly on the bar line lands in the chunk it opens and not also
            // in the one before.
            let slack = 0.5 / sampleRate
            let events = entries.compactMap { entry -> ToneSequence.Event? in
                guard let frequency = entry.frequency,
                      entry.start >= from - slack, entry.start < to - slack else { return nil }
                let room = to - entry.start
                return ToneSequence.Event(frequency: frequency,
                                          onset: max(0, entry.start - from),
                                          duration: Self.sounding(min(entry.duration, room)))
            }
            chunks.append(Chunk(startFrame: frame(from), frames: frames, events: events))
        }
        return chunks
    }
}
