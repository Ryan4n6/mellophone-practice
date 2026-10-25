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
    /// Where the page printed it (#43), so the card view can box it on the
    /// director's own page. Nil when it was not made from a glyph.
    var place: NotePlace?
    /// A hand clap, printed as an x notehead (#53). It has a rhythm and no
    /// pitch: `note` is nil and `writtenName` empty, as for a rest, but it
    /// sounds, so it is not one. Where the x sits on the staff means nothing.
    var isClap = false

    var isRest: Bool { note == nil && outOfRangeName == nil && !isClap }
    /// A note with a pitch: one to finger, to play and to check.
    var hasPitch: Bool { !isRest && !isClap }
    /// What a screen calls it: the page's name, "Clap" or "Rest".
    var displayName: String { isClap ? "Clap" : isRest ? "Rest" : writtenName }
}

/// Where a note or rest glyph sits on the page (#43). PDF user space, y up,
/// the glyph's origin, which for a notehead is its left edge on its line.
struct NotePlace: Equatable {
    /// Index into `Score.systems`.
    let system: Int
    let x: Double
    let y: Double
}

/// One bar's horizontal span on its line (#43): what a tap on the card hits.
struct BarSpan: Equatable {
    let measure: Int
    let x0: Double
    let x1: Double
}

/// One printed line of the part (#43), in reading order across pages.
///
/// The card view and the printed cards both cut lines out of the PDF from
/// this, so `inkTop` and `inkBottom` are the line's own ink: the tempo mark
/// over it and the dynamics under it, but not the title over the first line.
struct SystemPlace: Equatable {
    let page: Int
    /// Bottom line first, as StaffFitter keeps them.
    let lineYs: [Double]
    let xRange: ClosedRange<Double>
    let halfSpace: Double
    let inkTop: Double
    let inkBottom: Double
    let bars: [BarSpan]

    var topLineY: Double { lineYs.last ?? 0 }
    var bottomLineY: Double { lineYs.first ?? 0 }
    var firstMeasure: Int? { bars.first?.measure }
    var lastMeasure: Int? { bars.last?.measure }
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

/// The repeat signs and endings a page prints (#46), by the page's bar
/// numbers. What order they make is `PlayOrder`'s question, not this one's.
struct Repeats: Equatable {
    /// Bars that open with a start repeat, the dots to the right of the barline.
    var starts: Set<Int> = []
    /// Bars that close with an end repeat, the dots to the left.
    var ends: Set<Int> = []
    /// The first bar of each ending, and the times through it is played on:
    /// [1] for "1.", [1, 2] for "1. 2.".
    var endings: [Int: [Int]] = [:]

    var isEmpty: Bool { starts.isEmpty && ends.isEmpty && endings.isEmpty }
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
    /// Every printed line, in reading order (#43). Empty for a score built
    /// by hand in a test.
    let systems: [SystemPlace]
    /// Every repeat and ending the page prints (#46). Empty for a chart that
    /// plays straight through, which is most of them.
    let repeats: Repeats
    /// Every bar number the part has, in the order the page prints them.
    let pageBars: [Int]
    /// The bars in the order a band plays them, repeats taken (#46).
    let playOrder: [Int]

    init(events: [ScoreEvent], timeSignature: (beats: Int, unit: Int), keySignature: Int,
         voiceCount: Int, suspectMeasures: Set<Int>, unreadableSymbols: [UInt32],
         beatUnits: [Int: Int] = [:], tempos: [TempoChange] = [], systems: [SystemPlace] = [],
         repeats: Repeats = Repeats()) {
        self.events = events
        self.timeSignature = timeSignature
        self.keySignature = keySignature
        self.voiceCount = voiceCount
        self.suspectMeasures = suspectMeasures
        self.unreadableSymbols = unreadableSymbols
        self.beatUnits = beatUnits
        self.tempos = tempos.sorted { $0.onsetBeats < $1.onsetBeats }
        self.systems = systems
        self.repeats = repeats
        var numbers: [Int] = []
        for event in events where event.voice == 0 && numbers.last != event.measure {
            numbers.append(event.measure)
        }
        self.pageBars = numbers
        // Worked out once, here: the part screen asks for it on every redraw.
        self.playOrder = PlayOrder.bars(numbers, repeats: repeats)
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
