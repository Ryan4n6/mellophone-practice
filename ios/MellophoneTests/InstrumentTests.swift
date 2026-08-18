import XCTest
@testable import Mellophone

/// The instrument picker changes two things and must not change anything else:
/// the fingerings and the concert half of a scale's name.
final class InstrumentTests: XCTestCase {

    // MARK: - Fingerings against published charts

    /// Michael Droste / TrumpetStudio.com, transcribed from the chart. The
    /// mellophone shares it, which is the premise the whole app rests on.
    private let publishedTrumpet = [
        "F#3": "1+2+3", "G3": "1+3", "Ab3": "2+3", "A3": "1+2", "Bb3": "1", "B3": "2",
        "C4": "Open", "C#4": "1+2+3", "D4": "1+3", "Eb4": "2+3", "E4": "1+2", "F4": "1",
        "F#4": "2", "G4": "Open", "Ab4": "2+3", "A4": "1+2", "Bb4": "1", "B4": "2",
        "C5": "Open", "C#5": "1+2"
    ]

    /// "Single F Horn Fingerings", Stewart Schlazer, transcribed from the chart.
    /// Written pitch. Its D5 is given as "0 or 1"; the chart fingering here is
    /// the open one.
    private let publishedHorn = [
        "F#3": "2", "Gb3": "2", "G3": "Open", "Ab3": "2+3", "A3": "1+2",
        "Bb3": "1", "B3": "2", "C4": "Open", "C#4": "1+2", "Db4": "1+2", "D4": "1",
        "Eb4": "2", "E4": "Open", "F4": "1", "F#4": "2", "Gb4": "2", "G4": "Open",
        "Ab4": "2+3", "A4": "1+2", "Bb4": "1", "B4": "2", "C5": "Open",
        "C#5": "2", "Db5": "2", "D5": "Open", "Eb5": "2", "E5": "Open", "F5": "1"
    ]

    func testMellophoneMatchesThePublishedTrumpetChart() {
        for (name, fingering) in publishedTrumpet {
            XCTAssertEqual(Fingering.value(for: name, on: .mellophone), fingering, "\(name)")
        }
    }

    func testTrumpetMatchesThePublishedTrumpetChart() {
        for (name, fingering) in publishedTrumpet {
            XCTAssertEqual(Fingering.value(for: name, on: .trumpet), fingering, "\(name)")
        }
    }

    func testFrenchHornMatchesThePublishedHornChart() {
        for (name, fingering) in publishedHorn {
            XCTAssertEqual(Fingering.value(for: name, on: .frenchHorn), fingering, "\(name)")
        }
    }

    /// The derived mellophone chart and the stored table must agree. The stored
    /// table is the source of truth shared with the web version; the derivation
    /// is what the app actually renders. If they ever diverge, one of them is
    /// lying to a student.
    func testDerivationAgreesWithTheStoredTable() {
        for note in Note.all {
            XCTAssertEqual(
                Fingering.value(for: note, on: .mellophone), note.fingering,
                "\(note.name) is stored as \(note.fingering)"
            )
        }
    }

    /// Mellophone and trumpet share a chart. Horn does not, and that difference
    /// is the entire reason this issue existed.
    func testHornDiffersFromTheOthersWhereItShould() {
        for note in Note.all {
            XCTAssertEqual(
                Fingering.value(for: note, on: .mellophone),
                Fingering.value(for: note, on: .trumpet),
                "\(note.name): mellophone and trumpet must share a chart"
            )
        }
        // The notes a horn player would otherwise be taught wrong.
        XCTAssertEqual(Fingering.value(for: "E4", on: .frenchHorn), "Open")
        XCTAssertEqual(Fingering.value(for: "E4", on: .mellophone), "1+2")
        XCTAssertEqual(Fingering.value(for: "D5", on: .frenchHorn), "Open")
        XCTAssertEqual(Fingering.value(for: "D5", on: .mellophone), "1")
        XCTAssertEqual(Fingering.value(for: "G3", on: .frenchHorn), "Open")
        XCTAssertEqual(Fingering.value(for: "G3", on: .mellophone), "1+3")
    }

    /// F3 has no mellophone fingering, which is why it is not in the table. It
    /// DOES have one on a horn, whose series reaches lower, so nil must be a
    /// per-instrument answer rather than a property of the note.
    func testF3IsPlayableOnHornButNotOnMellophone() {
        XCTAssertNil(Fingering.value(for: "F3", on: .mellophone))
        XCTAssertNil(Fingering.value(for: "F3", on: .trumpet))
        XCTAssertEqual(Fingering.value(for: "F3", on: .frenchHorn), "1")
    }

    // MARK: - Concert keys

    /// Written F is concert Bb on an F instrument and concert Eb on a Bb
    /// trumpet. Getting this wrong puts a student in the wrong key next to a
    /// director, which is worse than a silent bug.
    func testConcertKeysPerInstrument() {
        let cases: [(written: String, mello: String, trumpet: String)] = [
            ("F", "Bb", "Eb"), ("Bb", "Eb", "Ab"), ("C", "F", "Bb"), ("Eb", "Ab", "Db")
        ]
        for c in cases {
            XCTAssertEqual(Scale.concertKey(forWritten: c.written, on: .mellophone), c.mello, "written \(c.written)")
            XCTAssertEqual(Scale.concertKey(forWritten: c.written, on: .frenchHorn), c.mello, "horn matches mellophone")
            XCTAssertEqual(Scale.concertKey(forWritten: c.written, on: .trumpet), c.trumpet, "written \(c.written)")
        }
    }

    /// The stored names are already correct for an F instrument, so relabelling
    /// must be a no-op there. That is the guard against a "fix" that quietly
    /// changes what the mellophone sees.
    func testScaleNamesAreUnchangedForFInstruments() {
        for scale in Scale.all {
            XCTAssertEqual(scale.displayName(for: .mellophone), scale.name, scale.name)
            XCTAssertEqual(scale.displayName(for: .frenchHorn), scale.name, scale.name)
        }
    }

    func testScaleNamesAreRecalculatedForTrumpet() {
        let scale = Scale.all.first { $0.name == "Concert Bb (Written F)" }
        XCTAssertEqual(scale?.displayName(for: .trumpet), "Concert Eb (Written F)")
    }

    /// Lip slurs and long tones are exercises, not keys, and must pass through
    /// untouched on every instrument.
    func testExerciseNamesAreNeverRewritten() {
        for scale in Scale.all where !scale.name.hasPrefix("Concert ") {
            for instrument in Instrument.allCases {
                XCTAssertEqual(scale.displayName(for: instrument), scale.name, scale.name)
            }
        }
    }
}
