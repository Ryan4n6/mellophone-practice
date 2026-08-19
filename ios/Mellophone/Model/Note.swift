import Foundation

/// How a note is spelled on the page. The symbol matters because the two
/// spellings of an enharmonic pair sit on different lines of the staff.
enum Accidental: String {
    case natural = ""
    case sharp = "#"
    case flat = "b"

    /// The character, for text contexts like a note-name label.
    ///
    /// NOT used to draw the staff. Coverage on iOS is uneven (25 faces carry
    /// U+266F, only 13 carry U+266D, and Times New Roman has the sharp but not
    /// the flat), so relying on font fallback can put the two accidentals in
    /// two different typefaces on the same staff. `StaffGeometry` draws them as
    /// paths instead.
    var glyph: String {
        switch self {
        case .natural: return ""
        case .sharp: return "\u{266F}"
        case .flat: return "\u{266D}"
        }
    }
}

/// One row of the table in `index.html`, which drives the fingering chart, the
/// range pickers, the drill pool, the harmonic-series card and scale playback.
struct Note: Identifiable, Hashable {
    let name: String
    /// The literal frequency of the named pitch. No F transposition is applied
    /// to the audio; the mellophone's transposition shows up only in the scale
    /// labels, which name both keys.
    let frequency: Double
    /// A staff coordinate, not a drawing coordinate. Counts diatonic steps down
    /// from the top of the drawing area in units of 10 (C6 = 0, F3 = 180).
    /// `StaffView` converts it. Enharmonic pairs deliberately differ: F#3 sits
    /// on the F line, Gb3 on the G line.
    let staffPosition: Int
    /// A display string that doubles as an equality key. "Same Fingering" is a
    /// filter on exact equality of this field, so the strings have to be written
    /// consistently: "1+2", never "2+1".
    let fingering: String
    let accidental: Accidental

    var id: String { name }

    /// Which valves are down. Reads the display string, exactly as the web
    /// version's `updateValves` does, so the two cannot disagree.
    func isValveDown(_ valve: Int) -> Bool {
        fingering.contains(String(valve))
    }

    var isOpen: Bool { fingering == "Open" }
}

extension Note {
    /// The notes a person picks from: the full table minus the flats that have a
    /// sharp spelling at the same frequency.
    ///
    /// Use this for anything the user chooses (range pickers, the fingering
    /// chart, the drill pool). Use `Note.all` for lookups and enharmonic
    /// matching, where both spellings have to be reachable.
    static let selectable: [Note] = all.filter { note in
        guard note.accidental == .flat else { return true }
        return !all.contains { $0.frequency == note.frequency && $0.accidental == .sharp }
    }

    static func named(_ name: String) -> Note? {
        all.first { $0.name == name }
    }

    /// Every spelling that sounds at this pitch, including this one.
    var enharmonics: [Note] {
        Note.all.filter { $0.frequency == frequency }
    }

    /// The inclusive slice of `selectable` between two notes, in either order.
    /// Mirrors `getRange()` in the web version.
    static func range(from low: String, to high: String) -> [Note] {
        guard
            let a = selectable.firstIndex(where: { $0.name == low }),
            let b = selectable.firstIndex(where: { $0.name == high })
        else { return selectable }
        return Array(selectable[min(a, b)...max(a, b)])
    }
}

/// A scale or exercise. Stores note NAMES and looks them up, the same way the
/// web version does, so a correction to a frequency in one place fixes it
/// everywhere.
struct Scale: Identifiable, Hashable {
    let name: String
    /// Plain English, one line: what this is and why you would play it.
    ///
    /// The names are the words a band director says out loud, so they stay as
    /// they are. "Lip Slurs (Open)" is findable by a kid who was told to run
    /// their lip slurs, and meaningless to one who has never heard the phrase.
    /// This is the half that fixes that, and it lives in the data next to the
    /// name so both products say the same thing (#15).
    let detail: String
    /// The one valve combination this exercise is played on, if it is that kind
    /// of exercise. Nil for scales, which change fingering constantly.
    ///
    /// This is NOT the same question as the chart fingering for each note. E5 is
    /// open on a mellophone AND is the sixth partial of the 1+2 series, so a 1+2
    /// lip slur that displayed the chart answer would tell a student to lift
    /// their fingers halfway through a slur, which is exactly what the exercise
    /// exists to stop. Found by ScalePitchTests (#16).
    let heldFingering: String?
    let noteNames: [String]

    var id: String { name }

    var notes: [Note] { noteNames.compactMap(Note.named) }
}
