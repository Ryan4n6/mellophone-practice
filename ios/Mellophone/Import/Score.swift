import Foundation

/// One sounding event, or a rest.
///
/// `note` is the app's existing Note, not a new pitch type, so an imported part
/// gets fingeringFor, staffPosition and frequency for free and renders on the
/// same staff as the trainer and the drill.
struct ScoreEvent: Identifiable {
    let id = UUID()
    let note: Note?
    /// The pitch as the PAGE spells it, which is not always how the app spells
    /// it. NoteData holds five sharps and writes everything else flat, so a
    /// written G#4 resolves to the Ab4 row: same frequency, same fingering,
    /// different line of the staff. Keeping both means playback can use the row
    /// the app knows while the UI can still draw what the director wrote.
    /// Empty for a rest.
    let writtenName: String
    /// Set when the page asked for a pitch outside F#3 to C6, which no row of
    /// NoteData can return. Without this a note above the horn's range would
    /// come back as note == nil and be played as SILENCE, which is the worst
    /// possible failure: the part would sound right apart from the bars Sam most
    /// needs to hear. The event keeps its duration and the UI shows the name
    /// greyed.
    let outOfRangeName: String?
    /// Beats from the start of the score, not from the start of the measure.
    let onsetBeats: Double
    let durationBeats: Double
    let measure: Int
    let voice: Int

    var isRest: Bool { note == nil && outOfRangeName == nil }
}

struct Score {
    let events: [ScoreEvent]
    /// The FIRST system's time signature. A chart is free to change meter, and
    /// ScoreBuilder applies each system's own; this is the one to show.
    let timeSignature: (beats: Int, unit: Int)
    /// Negative for flats, positive for sharps, zero for C. The first system's,
    /// for the same reason as `timeSignature`: PEAK mello.pdf changes from four
    /// flats to one at measure 65, and applying either value to the whole part
    /// transposes half of it.
    let keySignature: Int
    let voiceCount: Int
    /// Measures whose durations did not sum to the time signature. These render
    /// flagged and tappable rather than being silently played wrong. Filled in
    /// by the validator in Task 6, empty until then.
    let suspectMeasures: Set<Int>
    /// Codepoints the font table did not recognise, so a chart that defeats the
    /// reader can say which glyphs did it.
    let unreadableSymbols: [UInt32]

    static let empty = Score(events: [], timeSignature: (4, 4), keySignature: 0,
                             voiceCount: 0, suspectMeasures: [], unreadableSymbols: [])
}
