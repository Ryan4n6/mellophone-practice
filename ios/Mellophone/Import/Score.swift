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
    /// Tied from the note before it at the same pitch (#39): it is held on,
    /// not played again, and it takes that note's accidental, which a tied
    /// note never prints. PEAK bar 51 is an A tied from an A flat, and read
    /// without the tie it played a semitone sharp.
    var tiedFromPrevious = false

    var isRest: Bool { note == nil && outOfRangeName == nil }
}

/// A printed tempo, placed in the part (#41).
struct TempoChange: Equatable {
    /// The bar it is printed over, numbered as the page numbers it.
    let measure: Int
    /// Where in the part it takes effect, in the same running beats as
    /// `ScoreEvent.onsetBeats`, so a change in the middle of a bar lands on
    /// the note it is printed over and not on the barline before it.
    let onsetBeats: Double
    /// The number on the page.
    let printed: Int
    /// What the number counts, in quarter notes: 1 for "♩ =", 1.5 for "♩. =".
    let noteQuarters: Double

    var quartersPerMinute: Double { Double(printed) * noteQuarters }
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
    /// Which note value gets the beat in each measure: the bottom number of the
    /// time signature in force there. `durationBeats` counts in THAT unit, so
    /// an eighth note is one beat in 6/8 and half a beat in 4/4, and a part
    /// that changes from one to the other cannot be played back at a steady
    /// eighth without knowing where the change is. A measure with no entry
    /// takes the opening signature's.
    let beatUnits: [Int: Int]
    /// Every tempo the page prints, in the order they take effect (#41).
    /// Empty for a chart with no mark the reader could read, which then plays
    /// at the student's own number throughout.
    let tempos: [TempoChange]

    init(events: [ScoreEvent], timeSignature: (beats: Int, unit: Int), keySignature: Int,
         voiceCount: Int, suspectMeasures: Set<Int>, unreadableSymbols: [UInt32],
         beatUnits: [Int: Int] = [:], tempos: [TempoChange] = []) {
        self.events = events
        self.timeSignature = timeSignature
        self.keySignature = keySignature
        self.voiceCount = voiceCount
        self.suspectMeasures = suspectMeasures
        self.unreadableSymbols = unreadableSymbols
        self.beatUnits = beatUnits
        self.tempos = tempos.sorted { $0.onsetBeats < $1.onsetBeats }
    }

    func beatUnit(of measure: Int) -> Int { beatUnits[measure] ?? timeSignature.unit }

    /// The printed tempo in force at the start of `measure`, or nil before the
    /// first mark and on a chart with none.
    func tempo(at measure: Int) -> TempoChange? {
        tempos.last { $0.measure <= measure }
    }

    static let empty = Score(events: [], timeSignature: (4, 4), keySignature: 0,
                             voiceCount: 0, suspectMeasures: [], unreadableSymbols: [])
}
