import Foundation

/// Which horn the chart is being read for.
///
/// The app started as a mellophone tool, and most of it was already
/// instrument-agnostic without anyone intending that: the staff, the reading
/// drill, the metronome and the timer all depend on written pitch, not on the
/// instrument. Only two things actually differ, and this type holds both.
enum Instrument: String, CaseIterable, Identifiable {
    case mellophone
    case frenchHorn
    case trumpet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mellophone: return "Mellophone (F)"
        case .frenchHorn: return "French Horn (F)"
        case .trumpet: return "Trumpet (Bb)"
        }
    }

    var shortName: String {
        switch self {
        case .mellophone: return "Mello"
        case .frenchHorn: return "Horn"
        case .trumpet: return "Trumpet"
        }
    }

    /// Semitones a written note is lowered by to reach concert pitch.
    ///
    /// An instrument in F sounds a perfect fifth below written, so written F is
    /// concert Bb. A Bb trumpet sounds a major second below, so the same written
    /// F is concert Eb. Getting this wrong does not make a scale sound wrong on
    /// its own, it makes a student play in the wrong key next to a director.
    var transpositionSemitones: Int {
        switch self {
        case .mellophone, .frenchHorn: return 7
        case .trumpet: return 2
        }
    }

    /// The written notes that play open, with no valves down.
    ///
    /// This is the whole difference between the horn and the other two. A
    /// mellophone and a trumpet sit in the same place in the harmonic series
    /// relative to their written notes, so they share a chart. A French horn's F
    /// side sits an OCTAVE LOWER in the series, which packs far more partials
    /// into the staff and gives it many more open notes. Written E4 is open on a
    /// horn and 1+2 on the other two.
    ///
    /// The horn set omits the 7th, 11th, 13th and 14th partials, which are too
    /// far out of tune to be chart fingerings.
    var openPartials: [String] {
        switch self {
        case .mellophone, .trumpet:
            return ["C4", "G4", "C5", "E5", "G5", "C6"]
        case .frenchHorn:
            return ["G3", "C4", "E4", "G4", "C5", "D5", "E5", "G5", "C6"]
        }
    }

    /// Said plainly in the app, because every one of these will otherwise be
    /// discovered as a bug by a kid who trusted the screen.
    var caveat: String? {
        switch self {
        case .mellophone:
            return nil
        case .frenchHorn:
            return "F side fingerings. The Bb side of a double horn is different, and the horn plays lower than this chart goes."
        case .trumpet:
            return "Fingerings match the mellophone. Concert keys are recalculated for Bb."
        }
    }
}

/// Works out a fingering from the instrument's own harmonic series.
///
/// Deriving rather than storing is deliberate. Seven rows of the stored
/// mellophone table were wrong once (#9), and a table of remembered facts is
/// exactly the wrong shape for something this mechanical. `InstrumentTests`
/// checks this against the stored table AND against published charts for both
/// the trumpet and the single F horn.
enum Fingering {
    /// What each valve combination lowers a partial by, in semitones. Three
    /// valves reach six and no further.
    private static let bySemitone: [Int: String] = [
        0: "Open", 1: "2", 2: "1", 3: "1+2", 4: "2+3", 5: "1+3", 6: "1+2+3"
    ]

    private static let pitchClasses = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private static let enharmonic = ["Db": "C#", "D#": "Eb", "Gb": "F#", "G#": "Ab", "A#": "Bb"]

    static func semitoneValue(of name: String) -> Int? {
        guard let match = name.firstMatch(of: /^([A-G][b#]?)(\d)$/) else { return nil }
        var pitchClass = String(match.1)
        pitchClass = enharmonic[pitchClass] ?? pitchClass
        guard let index = pitchClasses.firstIndex(of: pitchClass), let octave = Int(match.2) else { return nil }
        return index + 12 * (octave + 1)
    }

    /// The fingering, or nil when three valves cannot reach the note from any
    /// partial. Nil is a real answer: written F3 has no mellophone fingering.
    static func value(for noteName: String, on instrument: Instrument) -> String? {
        guard let note = semitoneValue(of: noteName) else { return nil }
        var best: Int?
        for partial in instrument.openPartials {
            guard let partialValue = semitoneValue(of: partial) else { continue }
            let distance = partialValue - note
            if distance >= 0, distance <= 6, best == nil || distance < best! {
                best = distance
            }
        }
        return best.flatMap { bySemitone[$0] }
    }

    static func value(for note: Note, on instrument: Instrument) -> String? {
        value(for: note.name, on: instrument)
    }
}

extension Scale {
    /// The scale's name with the concert key recalculated for the instrument.
    ///
    /// Names are stored as "Concert Bb (Written F)", which is correct for an F
    /// instrument and WRONG for a trumpet, where written F is concert Eb. The
    /// written half is the fact; the concert half is derived from it.
    ///
    /// Anything without that shape, the lip slurs and long tones, is passed
    /// through untouched. Those are exercises, not keys.
    func displayName(for instrument: Instrument) -> String {
        guard let match = name.firstMatch(of: /^Concert (\S+) \(Written (\S+)\)$/) else {
            return name
        }
        let written = String(match.2)
        guard let concert = Self.concertKey(forWritten: written, on: instrument) else { return name }
        return "Concert \(concert) (Written \(written))"
    }

    /// Flat spellings throughout, which is how brass players name these keys.
    private static let flatSpellings = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    static func concertKey(forWritten written: String, on instrument: Instrument) -> String? {
        guard let value = Fingering.semitoneValue(of: written + "4") else { return nil }
        let concert = ((value - instrument.transpositionSemitones) % 12 + 12) % 12
        return flatSpellings[concert]
    }
}
