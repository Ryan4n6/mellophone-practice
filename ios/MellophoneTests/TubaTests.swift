import XCTest
@testable import Mellophone

/// The tuba and the bass clef euphonium (#72): two horns that read bass clef at
/// concert pitch, below the span the app was built for.
///
/// Every answer here is written out by hand or worked out in this file, never
/// asked of the code under test.
final class TubaTests: XCTestCase {

    // MARK: - Published charts

    /// "4 Valve & 3 Valve BBb Tuba, Euphonium & Sousaphone Basic Fingering
    /// Chart", Mouthpiece Express (cdn.shopify.com/s/files/1/0968/0109/5812/
    /// files/fingerings_tuba.pdf), rendered and read circle by circle on
    /// 2026-11-03. Bass clef, concert pitch, E1 to F4, three valve column,
    /// every spelling it prints.
    static let publishedTuba: [String: String] = [
        "E1": "1+2+3", "F1": "1+3", "F#1": "2+3", "Gb1": "2+3", "G1": "1+2", "G#1": "1", "Ab1": "1",
        "A1": "2", "A#1": "Open", "Bb1": "Open", "B1": "1+2+3", "C2": "1+3",
        "C#2": "2+3", "Db2": "2+3", "D2": "1+2", "D#2": "1", "Eb2": "1", "E2": "2", "F2": "Open",
        "F#2": "2+3", "Gb2": "2+3", "G2": "1+2", "G#2": "1", "Ab2": "1", "A2": "2",
        "A#2": "Open", "Bb2": "Open", "B2": "1+2", "C3": "1", "C#3": "2", "Db3": "2", "D3": "Open",
        "D#3": "1", "Eb3": "1", "E3": "2", "F3": "Open", "F#3": "2+3", "Gb3": "2+3", "G3": "1+2",
        "G#3": "1", "Ab3": "1", "A3": "2", "A#3": "Open", "Bb3": "Open", "B3": "1+2", "C4": "1",
        "C#4": "2", "Db4": "2", "D4": "Open", "D#4": "1", "Eb4": "1", "E4": "2", "F4": "Open"
    ]

    /// Same chart, the small circles: the four notes it gives a fourth valve
    /// fingering for. The app shows these in the tuba's caveat, not its chart,
    /// because nobody has said yet how many valves Ben's horn has.
    static let publishedTubaFourthValve: [String: String] = [
        "E1": "2+4", "F1": "4", "B1": "2+4", "C2": "4"
    ]

    /// The Mouthpiece Express euphonium chart, already pinned in
    /// `InstrumentTests` read a ninth up for the treble clef euphonium. The
    /// bass clef euphonium reads it as printed.
    static let publishedEuphonium: [String: String] = [
        "E2": "1+2+3", "F2": "1+3", "F#2": "2+3", "G2": "1+2", "Ab2": "1", "A2": "2", "Bb2": "Open",
        "B2": "1+2+3", "C3": "1+3", "C#3": "2+3", "D3": "1+2", "Eb3": "1", "E3": "2", "F3": "Open",
        "F#3": "2+3", "G3": "1+2", "Ab3": "1", "A3": "2", "Bb3": "Open", "B3": "1+2", "C4": "1",
        "C#4": "2", "D4": "Open", "Eb4": "1", "E4": "2", "F4": "Open", "F#4": "2+3", "G4": "1+2",
        "Ab4": "1", "A4": "2", "Bb4": "Open"
    ]

    func testTubaMatchesThePublishedTubaChart() {
        XCTAssertEqual(Self.publishedTuba.count, 53)
        for (name, fingering) in Self.publishedTuba {
            XCTAssertEqual(Fingering.value(for: name, on: .tuba), fingering, name)
        }
    }

    /// The control: the same chart read a semitone out must mostly disagree,
    /// or the test above could pass on any table at all. (An octave out is no
    /// control on a tuba: its series repeats by octaves, so half the chart
    /// agrees there anyway, measured 29 of 53.)
    func testTheTubaChartDoesNotMatchASemitoneOut() throws {
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        var wrong = 0
        for (name, fingering) in Self.publishedTuba {
            let up = try XCTUnwrap(Self.midi(name)) + 1
            if Fingering.value(for: "\(names[up % 12])\(up / 12 - 1)", on: .tuba) != fingering { wrong += 1 }
        }
        XCTAssertGreaterThan(wrong, 45)
    }

    func testBassClefEuphoniumMatchesThePublishedEuphoniumChartAsPrinted() {
        for (name, fingering) in Self.publishedEuphonium {
            XCTAssertEqual(Fingering.value(for: name, on: .euphoniumBass), fingering, name)
        }
    }

    /// Nothing a tuba or bass clef euphonium player is shown went unchecked.
    func testEveryNoteEachHornShowsIsOnItsChart() throws {
        for (instrument, chart) in [(Instrument.tuba, Self.publishedTuba),
                                    (Instrument.euphoniumBass, Self.publishedEuphonium)] {
            let checked = Set(try chart.keys.map { try XCTUnwrap(Self.midi($0)) })
            for note in instrument.notes {
                XCTAssertTrue(checked.contains(try XCTUnwrap(Self.midi(note.name))),
                              "\(note.name) is shown for \(instrument.rawValue) and not on its chart")
            }
        }
    }

    // MARK: - Range and clef

    func testEachHornHasItsClefAndItsSpan() {
        let expected: [Instrument: (Clef, String, String)] = [
            .mellophone: (.treble, "F#3", "C6"), .frenchHorn: (.treble, "F#3", "C6"),
            .trumpet: (.treble, "F#3", "C6"), .euphonium: (.treble, "F#3", "C6"),
            .euphoniumBass: (.bass, "E2", "Bb4"), .tuba: (.bass, "E1", "F4")
        ]
        XCTAssertEqual(Set(expected.keys), Set(Instrument.allCases))
        for (instrument, (clef, low, high)) in expected {
            XCTAssertEqual(instrument.clef, clef, instrument.rawValue)
            XCTAssertEqual(instrument.selectable.first?.name, low, instrument.rawValue)
            XCTAssertEqual(instrument.selectable.last?.name, high, instrument.rawValue)
        }
    }

    /// The treble horns see exactly the 31 notes they saw before the table
    /// grew. This is the guard against a mellophone range picker that starts
    /// offering E1.
    func testTheTrebleHornsListsAreUnchanged() {
        let before = ["F#3", "G3", "Ab3", "A3", "Bb3", "B3", "C4", "C#4", "D4", "Eb4", "E4", "F4",
                      "F#4", "G4", "Ab4", "A4", "Bb4", "B4", "C5", "C#5", "D5", "Eb5", "E5", "F5",
                      "F#5", "G5", "Ab5", "A5", "Bb5", "B5", "C6"]
        for instrument in [Instrument.mellophone, .frenchHorn, .trumpet, .euphonium] {
            XCTAssertEqual(instrument.selectable.map(\.name), before, instrument.rawValue)
            XCTAssertEqual(instrument.notes.count, 36, "\(instrument.rawValue): both spellings, as before")
        }
    }

    func testBassHornsSoundAsWritten() {
        for instrument in [Instrument.tuba, .euphoniumBass] {
            XCTAssertEqual(instrument.transpositionSemitones, 0, instrument.rawValue)
            XCTAssertEqual(instrument.sounding(58.27), 58.27, accuracy: 1e-9, instrument.rawValue)
        }
    }

    /// The working range: the mellophone's C4 to G5, moved to the same place
    /// in each horn's series. C4 is a mellophone's open second partial; Bb1 is
    /// a tuba's.
    func testDefaultRanges() {
        XCTAssertEqual(Instrument.mellophone.defaultRange.low, "C4")
        XCTAssertEqual(Instrument.mellophone.defaultRange.high, "G5")
        XCTAssertEqual(Instrument.tuba.defaultRange.low, "Bb1")
        XCTAssertEqual(Instrument.tuba.defaultRange.high, "F3")
        XCTAssertEqual(Instrument.euphoniumBass.defaultRange.low, "Bb2")
        XCTAssertEqual(Instrument.euphoniumBass.defaultRange.high, "F4")
    }

    /// A range saved for one horn is kept on another only when the new horn
    /// plays every note of it.
    func testASavedRangeOutsideTheHornResetsToItsDefault() {
        XCTAssertTrue(Instrument.tuba.keeps(low: "C2", high: "C3"))
        XCTAssertFalse(Instrument.tuba.keeps(low: "C4", high: "G5"), "a mellophone range on a tuba")
        XCTAssertFalse(Instrument.mellophone.keeps(low: "Bb1", high: "F3"), "a tuba range on a mellophone")
        XCTAssertTrue(Instrument.trumpet.keeps(low: "C4", high: "G5"))
        XCTAssertFalse(Instrument.tuba.keeps(low: "C2", high: "Nope"))
        XCTAssertEqual(Instrument.tuba.range(from: "C4", to: "G5").map(\.name).first, "Bb1",
                       "a range the horn cannot play falls back to its default")
        XCTAssertEqual(Instrument.tuba.range(from: "C3", to: "C2").map(\.name).first, "C2", "either order")
    }

    // MARK: - The note table below the staff

    /// Every row, old and new: the frequency is equal temperament from A440 and
    /// the staff position is the letter's, worked out here from the name.
    func testEveryRowIsTheNoteItNames() throws {
        let letters = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6]
        for note in Note.all {
            let midi = try XCTUnwrap(Self.midi(note.name), note.name)
            XCTAssertEqual(note.frequency, 440 * pow(2, Double(midi - 69) / 12), accuracy: 0.006, note.name)
            let octave = try XCTUnwrap(Int(String(note.name.last!)))
            let letter = try XCTUnwrap(letters[String(note.name.first!)])
            // C6 is 0 and each step down is 10.
            XCTAssertEqual(note.staffPosition, (6 * 7 - (octave * 7 + letter)) * 10, note.name)
        }
        XCTAssertEqual(Note.named("E1")?.staffPosition, 330)
        XCTAssertEqual(Note.named("F3")?.staffPosition, 180)
        XCTAssertEqual(Note.named("Bb1")?.frequency ?? 0, 58.27, accuracy: 0.005)
    }

    // MARK: - Scales

    /// Every exercise is playable on every horn: each note it names is a row,
    /// and a row that horn plays.
    func testEveryScaleIsInEveryHornsRange() {
        for instrument in Instrument.allCases {
            let span = Set(instrument.notes.map(\.name))
            for scale in Scale.all {
                let notes = scale.notes(on: instrument)
                XCTAssertEqual(notes.count, scale.noteNames.count, "\(scale.name) on \(instrument.rawValue)")
                for note in notes {
                    XCTAssertTrue(span.contains(note.name), "\(scale.name) on \(instrument.rawValue): \(note.name)")
                }
            }
        }
    }

    /// A lip slur is the open series on every horn, which is what the exercise
    /// is. On a tuba that starts on Bb1.
    func testTheTubaLipSlurIsItsOpenSeries() throws {
        let slur = try XCTUnwrap(Scale.all.first { $0.name == "Lip Slurs (Open)" })
        XCTAssertEqual(slur.notes(on: .tuba).map(\.name),
                       ["Bb1", "F2", "Bb2", "D3", "F3", "D3", "Bb2", "F2", "Bb1"])
        XCTAssertEqual(slur.notes(on: .euphoniumBass).map(\.name),
                       ["Bb2", "F3", "Bb3", "D4", "F4", "D4", "Bb3", "F3", "Bb2"])
        XCTAssertEqual(slur.notes(on: .mellophone).map(\.name), slur.noteNames, "the treble horns are untouched")
        // And held on one fingering the whole way, on both: the reason a
        // lip slur exists (#16).
        for scale in Scale.all {
            guard let hold = scale.heldFingering else { continue }
            for instrument in [Instrument.tuba, .euphoniumBass] {
                for note in scale.notes(on: instrument) {
                    XCTAssertTrue(Self.isOnSeries(note.name, of: hold, on: instrument),
                                  "\(scale.name) on \(instrument.rawValue): \(note.name) is not on the \(hold) series")
                }
            }
        }
    }

    /// The written F scale is concert Eb on any Bb horn, and the bass clef ones
    /// read concert, so it is shown as Eb with no written half.
    func testBassHornsScalesAreNamedByConcertKeyOnly() throws {
        let scale = try XCTUnwrap(Scale.all.first { $0.name == "Concert Bb (Written F)" })
        XCTAssertEqual(scale.displayName(for: .tuba, naming: .letters), "Concert Eb")
        XCTAssertEqual(scale.displayName(for: .euphoniumBass, naming: .letters), "Concert Eb")
        XCTAssertEqual(scale.notes(on: .tuba).map(\.name), ["Eb2", "F2", "G2", "Ab2", "Bb2", "C3", "D3", "Eb3"])
        XCTAssertEqual(scale.displayName(for: .trumpet, naming: .letters), "Concert Eb (Written F)", "unchanged")
    }

    // MARK: - The card and the tuner

    func testSameFingeringOnATubaIsItsOpenSeries() throws {
        let bb1 = try XCTUnwrap(Note.named("Bb1"))
        XCTAssertEqual(Set(bb1.sameFingering(on: .tuba).map(\.name)), ["F2", "Bb2", "D3", "F3", "Bb3", "D4", "F4"])
    }

    /// The card is the horn's own notes. C4 on a mellophone must not pick up
    /// rows from below the treble staff that only a tuba plays.
    func testSameFingeringStaysInTheHornsSpan() throws {
        let c4 = try XCTUnwrap(Note.named("C4"))
        for instrument in Instrument.allCases {
            let span = Set(instrument.notes.map(\.name))
            for other in c4.sameFingering(on: instrument) {
                XCTAssertTrue(span.contains(other.name), "\(other.name) on \(instrument.rawValue)")
            }
        }
    }

    func testTubaTuningNotesAreOpenAndSoundTheirConcertPitch() throws {
        XCTAssertEqual(Instrument.tuba.tuningNotes.map(\.writtenName), ["Bb2", "F2"])
        XCTAssertEqual(Instrument.euphoniumBass.tuningNotes.map(\.writtenName), ["Bb3", "F3"])
        for instrument in [Instrument.tuba, .euphoniumBass] {
            for tuning in instrument.tuningNotes {
                XCTAssertEqual(Fingering.value(for: tuning.writtenName, on: instrument), "Open")
                XCTAssertEqual(String(tuning.writtenName.dropLast()), tuning.concert)
            }
        }
    }

    // MARK: - Helpers, independent of the app

    /// MIDI number from a name, worked out here.
    static func midi(_ name: String) -> Int? {
        let classes = ["C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
                       "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11]
        guard let octave = Int(String(name.last!)), let pc = classes[String(name.dropLast())] else { return nil }
        return pc + 12 * (octave + 1)
    }

    /// A note a lip slur may hold through: on the held combination's series,
    /// which is the open series lowered by what that combination lowers.
    static func isOnSeries(_ name: String, of hold: String, on instrument: Instrument) -> Bool {
        let lowers = ["Open": 0, "2": 1, "1": 2, "1+2": 3, "2+3": 4, "1+3": 5, "1+2+3": 6]
        guard let drop = lowers[hold], let note = midi(name) else { return false }
        return instrument.openPartials.contains { midi($0).map { $0 - drop == note } ?? false }
    }
}
