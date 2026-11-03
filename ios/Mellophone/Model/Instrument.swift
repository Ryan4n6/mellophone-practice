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
    case euphonium
    /// The same horn reading BASS clef at concert pitch (#72).
    case euphoniumBass
    /// A BBb tuba, and a sousaphone, which is fingered the same (#72).
    case tuba

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mellophone: return String(localized: "Mellophone (F)")
        case .frenchHorn: return String(localized: "French Horn (F)")
        case .trumpet: return String(localized: "Trumpet (Bb)")
        case .euphonium: return String(localized: "Euphonium T.C. (Bb)")
        case .euphoniumBass: return String(localized: "Euphonium B.C. (Bb)")
        case .tuba: return String(localized: "Tuba / Sousaphone (BBb)")
        }
    }

    var shortName: String {
        switch self {
        case .mellophone: return String(localized: "Mello", comment: "Short name of the mellophone, on the instrument chip")
        case .frenchHorn: return String(localized: "Horn", comment: "Short name of the French horn, on the instrument chip")
        case .trumpet: return String(localized: "Trumpet", comment: "Short name of the trumpet, on the instrument chip")
        case .euphonium: return String(localized: "Euph", comment: "Short name of the euphonium, on the instrument chip")
        case .euphoniumBass: return String(localized: "Euph B.C.", comment: "Short name of the bass clef euphonium, on the instrument chip")
        case .tuba: return String(localized: "Tuba", comment: "Short name of the tuba, on the instrument chip")
        }
    }

    /// The horn as a sentence names it: "the pitch your mello makes". Its own
    /// word and not `shortName.lowercased()`, because French puts the gender
    /// on the possessive, "ton mellophone" but "ta trompette", so in French
    /// this word carries its possessive and the sentences around it do not
    /// (#67). Spanish "tu" has no gender and stays in the sentence.
    var inSentence: String {
        switch self {
        case .mellophone: return String(localized: "mello", comment: "The mellophone inside a sentence: 'the pitch your mello makes'")
        case .frenchHorn: return String(localized: "horn", comment: "The French horn inside a sentence")
        case .trumpet: return String(localized: "trumpet", comment: "The trumpet inside a sentence")
        case .euphonium, .euphoniumBass: return String(localized: "euph", comment: "The euphonium inside a sentence")
        case .tuba: return String(localized: "tuba", comment: "The tuba inside a sentence")
        }
    }

    /// Semitones a written note is lowered by to reach concert pitch.
    ///
    /// An instrument in F sounds a perfect fifth below written, so written F is
    /// concert Bb. A Bb trumpet sounds a major second below, so the same written
    /// F is concert Eb. Getting this wrong does not make a scale sound wrong on
    /// its own, it makes a student play in the wrong key next to a director.
    ///
    /// A euphonium reading TREBLE clef is a trumpet an octave down: the same
    /// written notes and the same valves, sounding a major ninth below the
    /// page. One reading bass clef plays the same valves under different
    /// note names on a different staff, at concert pitch (#72), and so does
    /// the tuba: for both, the page IS the sound.
    var transpositionSemitones: Int {
        switch self {
        case .mellophone, .frenchHorn: return 7
        case .trumpet: return 2
        case .euphonium: return 14
        case .euphoniumBass, .tuba: return 0
        }
    }

    /// The frequency this instrument puts into the room for a written one.
    ///
    /// The one place the factor is worked out. The note check listens for it
    /// and a chart is played at it (#24), and the two have to be the same
    /// number or the app tells a student they are flat against its own sound.
    func sounding(_ written: Double) -> Double {
        written * pow(2, -Double(transpositionSemitones) / 12)
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
    /// The horn set omits the 7th, 11th, 13th, 14th and 15th partials. The first
    /// four are too far out of tune to be chart fingerings. The 15th (written
    /// B5) is playable, but published single F horn charts give B5 as 2 rather
    /// than open, so leaving it out is what reproduces the chart a student will
    /// be handed. Checked against the Mouthpiece Express single F chart, which
    /// agrees with this table on all 31 notes in range.
    var openPartials: [String] {
        switch self {
        // The euphonium's chart is the trumpet's, which is the whole reason
        // treble clef baritone parts exist: a trumpet player can pick one up
        // and read. Checked against the Mouthpiece Express euphonium chart,
        // which is printed in bass clef at concert pitch and agrees a major
        // ninth down on all 31 of its notes.
        case .mellophone, .trumpet, .euphonium:
            return ["C4", "G4", "C5", "E5", "G5", "C6"]
        case .frenchHorn:
            return ["G3", "C4", "E4", "G4", "C5", "D5", "E5", "G5", "C6"]
        // The 2nd, 3rd, 4th, 5th, 6th and 8th partials, as the euphonium
        // chart prints them in bass clef (`TubaTests`).
        case .euphoniumBass:
            return ["Bb2", "F3", "Bb3", "D4", "F4", "Bb4"]
        // The euphonium's series an octave down, which is what a BBb tuba
        // is, and on up to the 10th and 12th for the top of its chart: the
        // Mouthpiece Express tuba chart gives D4 and F4 open and C4 as 1, so
        // the 9th partial is left out the way the trumpet's 7th is.
        case .tuba:
            return ["Bb1", "F2", "Bb2", "D3", "F3", "Bb3", "D4", "F4"]
        }
    }

    /// Said plainly in the app, because every one of these will otherwise be
    /// discovered as a bug by a kid who trusted the screen.
    var caveat: String? {
        switch self {
        case .mellophone:
            return nil
        case .frenchHorn:
            return String(localized: "F side fingerings. The Bb side of a double horn is different, and the horn plays lower than this chart goes.")
        case .trumpet:
            return String(localized: "Fingerings match the mellophone. Concert keys are recalculated for Bb.")
        case .euphonium:
            return String(localized: "For treble clef parts, read like a trumpet. For bass clef parts, pick Euphonium B.C. With a fourth valve, 4 replaces 1+3 and 2+4 replaces 1+2+3.")
        case .euphoniumBass:
            return String(localized: "For bass clef parts, at concert pitch. With a fourth valve, 4 replaces 1+3 and 2+4 replaces 1+2+3.")
        // From the small circles on the tuba chart, which give a fourth
        // valve fingering for these four notes only.
        case .tuba:
            return String(localized: "A sousaphone is fingered the same. With a fourth valve, play 4 for low F and C, and 2+4 for low E and B.")
        }
    }
}

/// A note a band tunes to, and what one horn plays to make it (#32).
struct TuningNote: Identifiable, Equatable {
    /// The concert pitch the director calls out, as they say it: "F" or "Bb".
    let concert: String
    /// What this horn reads, and fingers, for that sound.
    let writtenName: String

    var id: String { concert }
}

extension Instrument {
    /// The two notes a band is tuned to, as THIS horn reads them.
    ///
    /// A director says "concert F" or "concert Bb" to a room of instruments
    /// in four different keys, and working out what that means on the horn in
    /// your hands is the first thing a new player gets wrong. So the answer
    /// is written down here, per horn, and `NoteCheckTests` checks each row
    /// sounds the pitch it claims against the published frequencies.
    ///
    /// The first one is the OPEN note, written C5 on the four treble horns
    /// and Bb on the two that read concert pitch. It is
    /// the one to move the main tuning slide by: a note with a valve down is
    /// also tuned by that valve's own slide, and a student who pulls the main
    /// slide to fix it has detuned every open note to do so. That is why the
    /// order differs: on a horn in F the open C is concert F, on one in Bb it
    /// is concert Bb.
    var tuningNotes: [TuningNote] {
        switch self {
        case .mellophone, .frenchHorn:
            return [TuningNote(concert: "F", writtenName: "C5"), TuningNote(concert: "Bb", writtenName: "F4")]
        case .trumpet, .euphonium:
            return [TuningNote(concert: "Bb", writtenName: "C5"), TuningNote(concert: "F", writtenName: "G4")]
        // Both open, the 4th and 3rd partials: the notes a tuba section is
        // actually tuned on, not the bottom of the horn.
        case .euphoniumBass:
            return [TuningNote(concert: "Bb", writtenName: "Bb3"), TuningNote(concert: "F", writtenName: "F3")]
        case .tuba:
            return [TuningNote(concert: "Bb", writtenName: "Bb2"), TuningNote(concert: "F", writtenName: "F2")]
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

    /// A fingering as the student reads it (#67). The value stays "Open" or
    /// "1+2": it is an equality key for the Same Fingering card and lights
    /// the valve drawing. Only the word for no valves down is translated.
    static func shown(_ value: String) -> String {
        value == "Open" ? String(localized: "Open", comment: "A fingering: no valves down") : value
    }
}

extension Note {
    /// The other notes that take the same valve combination ON `instrument`.
    ///
    /// This is the harmonic-series card. Its entire purpose is being right about
    /// which notes the valves will NOT separate, so the player's ear and
    /// embouchure have to, and that set is per instrument: a French horn's open
    /// series is longer than a mellophone's, so it separates notes a mellophone
    /// cannot.
    ///
    /// It lives here rather than on `Note` because `Note` knows nothing about
    /// instruments and should not start. The version that used to sit there
    /// filtered on the stored mellophone `fingering` column, which was right for
    /// one of the three instruments and silently wrong for the horn (#13).
    func sameFingering(on instrument: Instrument) -> [Note] {
        guard let mine = Fingering.value(for: self, on: instrument) else { return [] }
        return instrument.notes.filter { other in
            other.name != name && Fingering.value(for: other, on: instrument) == mine
        }
    }
}

extension Scale {
    /// The scale's name with the concert key recalculated for the instrument.
    ///
    /// Names are stored as "Concert Bb (Written F)", which is correct for an F
    /// instrument and WRONG for a trumpet, where written F is concert Eb. The
    /// written half is the fact; the concert half is derived from it.
    ///
    /// Anything without that shape, the lip slurs and long tones, is an
    /// exercise and not a key, and shows its translated name.
    ///
    /// Both keys are shown in `naming` (#67): "Concert Bb (Written F)" is
    /// "Si♭ de concierto (escrito Fa)" to a student reading in solfège.
    func displayName(for instrument: Instrument, naming: NoteNaming = .current) -> String {
        guard let match = name.firstMatch(of: /^Concert (\S+) \(Written (\S+)\)$/) else {
            return shownName ?? name
        }
        let written = String(match.2)
        guard let concert = Self.concertKey(forWritten: written, on: instrument) else { return name }
        let concertShown = naming.showKey(concert), writtenShown = naming.showKey(written)
        // A horn whose page is the sound has no written half to show (#27).
        if instrument.transpositionSemitones == 0 {
            return String(localized: "Concert \(concertShown)")
        }
        return String(localized: "Concert \(concertShown) (Written \(writtenShown))",
                      comment: "A scale's name: the key the band hears, then the key this horn reads")
    }

    /// Flat spellings throughout, which is how brass players name these keys.
    private static let flatSpellings = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// The stored written key moved to this horn's page first, then to
    /// concert. Written F is Eb on a tuba's page and Eb in the room, the
    /// same Eb a trumpet's written F sounds, since both are horns in Bb.
    static func concertKey(forWritten written: String, on instrument: Instrument) -> String? {
        guard let value = Fingering.semitoneValue(of: written + "4") else { return nil }
        let concert = ((value + instrument.scaleShift.semitones - instrument.transpositionSemitones) % 12 + 12) % 12
        return flatSpellings[concert]
    }

    /// The notes of this exercise as `instrument` reads them. The stored names
    /// are the trumpet's written notes, which is every treble horn's page; a
    /// horn that reads bass clef gets them moved down to where it plays, so a
    /// lip slur is still its own open series (#72).
    func notes(on instrument: Instrument) -> [Note] {
        let shift = instrument.scaleShift
        guard shift.semitones != 0 else { return notes }
        let moved = noteNames.compactMap { Note.transposedName($0, semitones: shift.semitones, steps: shift.steps) }
            .compactMap(Note.named)
        if moved.count != noteNames.count {
            Log.store.error("[SCALES] \(name, privacy: .public) has \(noteNames.count - moved.count, privacy: .public) note(s) with no row on \(instrument.rawValue, privacy: .public)")
        }
        return moved
    }
}

/// The staff a horn's part is printed on (#72).
enum Clef: String {
    case treble
    case bass
}

extension Instrument {
    var clef: Clef {
        switch self {
        case .mellophone, .frenchHorn, .trumpet, .euphonium: return .treble
        case .euphoniumBass, .tuba: return .bass
        }
    }

    /// The lowest and highest note this horn is shown, as its page names them.
    ///
    /// The four treble horns keep the span the app was built on, F#3 to C6,
    /// which a horn plays lower than and the chart says so. The bass horns'
    /// spans are their published charts' (`TubaTests`): the bass clef
    /// euphonium E2 to Bb4, the tuba E1 to F4.
    var span: (low: String, high: String) {
        switch self {
        case .mellophone, .frenchHorn, .trumpet, .euphonium: return ("F#3", "C6")
        case .euphoniumBass: return ("E2", "Bb4")
        case .tuba: return ("E1", "F4")
        }
    }

    /// Every row of the table inside the span, both spellings. The table
    /// holds every horn's notes (#72), so anything a student picks from or is
    /// drilled on goes through this, never through `Note.all`.
    var notes: [Note] {
        guard let low = Note.named(span.low)?.frequency, let high = Note.named(span.high)?.frequency else { return [] }
        return Note.all.filter { $0.frequency >= low - 0.001 && $0.frequency <= high + 0.001 }
    }

    /// The notes a student picks from: `notes` without the flats that have a
    /// sharp at the same pitch, as `Note.selectable` does for the table.
    var selectable: [Note] {
        let mine = Set(notes.map(\.name))
        return Note.selectable.filter { mine.contains($0.name) }
    }

    /// The working range a new player starts with: the mellophone's C4 to G5,
    /// moved to the same place in each horn's series. C4 is the mellophone's
    /// open 2nd partial, Bb1 the tuba's.
    var defaultRange: (low: String, high: String) {
        switch self {
        case .mellophone, .frenchHorn, .trumpet, .euphonium: return ("C4", "G5")
        case .euphoniumBass: return ("Bb2", "F4")
        case .tuba: return ("Bb1", "F3")
        }
    }

    /// Whether a saved practice range still makes sense on this horn: both
    /// ends are notes it is shown. A mellophone's C4 to G5 on a tuba is not.
    func keeps(low: String, high: String) -> Bool {
        let mine = Set(selectable.map(\.name))
        return mine.contains(low) && mine.contains(high)
    }

    /// The practice range, low and high in either order, or this horn's
    /// default when the saved one is not a range it plays.
    func range(from low: String, to high: String) -> [Note] {
        let ends = keeps(low: low, high: high) ? (low, high) : defaultRange
        let list = selectable
        guard let a = list.firstIndex(where: { $0.name == ends.0 }),
              let b = list.firstIndex(where: { $0.name == ends.1 }) else { return list }
        return Array(list[min(a, b)...max(a, b)])
    }

    /// How the stored exercises, written for the treble horns, move to this
    /// horn's page: in semitones, and in staff steps so the spelling follows.
    /// The tuba is a trumpet two octaves and a tone down (C4 open on one, Bb1
    /// on the other), the bass clef euphonium a ninth down.
    var scaleShift: (semitones: Int, steps: Int) {
        switch self {
        case .mellophone, .frenchHorn, .trumpet, .euphonium: return (0, 0)
        case .euphoniumBass: return (-14, -8)
        case .tuba: return (-26, -15)
        }
    }
}

extension Note {
    /// A note name moved by an interval, spelled by the interval: C4 down a
    /// tone and two octaves is Bb1, not A#1. Nil when the spelling would need
    /// a double sharp or flat, which no row of the table has.
    static func transposedName(_ name: String, semitones: Int, steps: Int) -> String? {
        let letters = ["C", "D", "E", "F", "G", "A", "B"]
        let naturals = [0, 2, 4, 5, 7, 9, 11]
        guard let match = name.firstMatch(of: /^([A-G])([b#]?)(\d)$/),
              let letter = letters.firstIndex(of: String(match.1)),
              let octave = Int(match.3) else { return nil }
        let bend = match.2 == "#" ? 1 : match.2 == "b" ? -1 : 0
        let target = naturals[letter] + bend + 12 * (octave + 1) + semitones
        let step = octave * 7 + letter + steps
        let newLetter = ((step % 7) + 7) % 7
        let newOctave = Int((Double(step) / 7).rounded(.down))
        switch target - (naturals[newLetter] + 12 * (newOctave + 1)) {
        case 0: return "\(letters[newLetter])\(newOctave)"
        case 1: return "\(letters[newLetter])#\(newOctave)"
        case -1: return "\(letters[newLetter])b\(newOctave)"
        default: return nil
        }
    }
}

extension Instrument {
    /// The lowest the tone's filter closes to when this horn's page is played.
    ///
    /// The tone's filter follows the note, so a bass horn's notes are rendered
    /// as a low hum with almost nothing above it, and a phone speaker makes
    /// nothing under about 300 Hz: a tuba's E1 played as a mellophone's would
    /// be silence on the phone. The note check's reference tone and a chart
    /// already hold it open to the same 700 Hz for the same reason (#24, #32).
    /// The treble horns get the samples they always did.
    var brightnessFloor: Double {
        clef == .bass ? NoteCheck.referenceBrightnessFloor : 0
    }
}
