import Foundation

/// How a note's name is SHOWN (#67). The stored name, "Bb4", is data: the
/// fingering derivation, the drill's answer check, the saved range and the
/// chart reader all compare it, and none of that changes with the language.
/// This only decides what the student reads.
///
/// In Spanish and French a note is read in solfège, Do Re Mi Fa Sol La Si,
/// and a student taught that way does not read "C". The two languages also
/// number octaves differently, which is measured, not assumed:
/// - Spanish in the Americas uses the scientific index, middle C is Do4,
///   the same number as C4 (es.wikipedia "Índice acústico científico": every
///   American country uses it; Spain uses it alongside the Franco-Belgian).
/// - French uses the Franco-Belgian index, middle C is Do3, one under C4.
/// Showing a French student Do4 for middle C would put every note an octave
/// off from their teacher's.
enum NoteNaming: String, CaseIterable, Identifiable {
    /// C D E, the names on a US band director's whiteboard.
    case letters
    /// Do Re Mi, numbered the Spanish (scientific) way: middle C is Do4.
    case solfege
    /// Do Ré Mi, numbered the French (Franco-Belgian) way: middle C is Do3.
    case solfegeFrench

    var id: String { rawValue }

    /// What a new install shows: solfège where the language reads notes that
    /// way. A Spanish speaker in a US band, taught C D E, switches it once in
    /// the Trainer.
    static func `default`(forLanguage code: String?) -> NoteNaming {
        switch code {
        case "es": return .solfege
        case "fr": return .solfegeFrench
        default: return .letters
        }
    }

    private static let syllables: [Character: (es: String, fr: String)] = [
        "C": ("Do", "Do"), "D": ("Re", "Ré"), "E": ("Mi", "Mi"), "F": ("Fa", "Fa"),
        "G": ("Sol", "Sol"), "A": ("La", "La"), "B": ("Si", "Si"),
    ]

    /// "Bb4" as this naming shows it: "Bb4", "Si♭4" or "Si♭3". A name that is
    /// not a note (a fingering, "?", a blank) comes back as it went in.
    func show(_ name: String) -> String {
        guard let match = name.firstMatch(of: /^([A-G])([b#]?)(-?\d)?$/) else { return name }
        let letter = match.1.first!
        let accidental = String(match.2)
        let octave = match.3.flatMap { Int($0) }
        switch self {
        case .letters:
            return name
        case .solfege, .solfegeFrench:
            let pair = Self.syllables[letter]!
            let syllable = self == .solfege ? pair.es : pair.fr
            let mark = accidental == "b" ? "\u{266D}" : accidental == "#" ? "\u{266F}" : ""
            let number = octave.map { String(self == .solfegeFrench ? $0 - 1 : $0) } ?? ""
            return syllable + mark + number
        }
    }

    /// A pitch class with no octave, "Bb" or "Si♭", for a key name.
    func showKey(_ pitchClass: String) -> String { show(pitchClass) }

    /// The setting's own label, in its own words.
    var label: String {
        switch self {
        case .letters: return String(localized: "C D E")
        case .solfege: return String(localized: "Do Re Mi (Do4 is middle C)")
        case .solfegeFrench: return String(localized: "Do Ré Mi (Do3 is middle C)")
        }
    }
}

extension NoteNaming {
    /// What the student chose, read where a view has no `Preferences` to hand
    /// (a model's sentence about a note).
    static var current: NoteNaming { Preferences.shared.noteNaming }
}
