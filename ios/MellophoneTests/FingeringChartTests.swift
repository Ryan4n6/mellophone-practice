import XCTest
@testable import Mellophone

/// The fingering chart is fully derivable, so it is checked rather than trusted.
///
/// Seven rows were wrong once (issue #9). F#3, Gb3, G3 and Ab3 carried a
/// neighbouring note's fingering, C#4 and Db4 used the combination that is only
/// correct an octave higher, and F3 was in the table at all despite having no
/// three-valve fingering. The drill prints these as corrective feedback, so a
/// wrong value does not merely fail to help, it teaches the wrong thing.
final class FingeringChartTests: XCTestCase {

    /// Open, no valves. Every other note is the nearest partial ABOVE it,
    /// lowered by valves.
    private let openPartials = ["C4", "G4", "C5", "E5", "G5", "C6"]

    /// Three valves reach six semitones and no further.
    private let valvesBySemitone = [
        0: "Open", 1: "2", 2: "1", 3: "1+2", 4: "2+3", 5: "1+3", 6: "1+2+3"
    ]

    private let pitchClasses = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private let enharmonic = ["Db": "C#", "D#": "Eb", "Gb": "F#", "G#": "Ab", "A#": "Bb"]

    private func midi(_ name: String) -> Int {
        let pattern = /^([A-G][b#]?)(\d)$/
        guard let match = name.firstMatch(of: pattern) else {
            XCTFail("cannot parse \(name)"); return 0
        }
        var pitchClass = String(match.1)
        pitchClass = enharmonic[pitchClass] ?? pitchClass
        let octave = Int(match.2)!
        return pitchClasses.firstIndex(of: pitchClass)! + 12 * (octave + 1)
    }

    private func expectedFingering(_ name: String) -> String? {
        let note = midi(name)
        var best: Int?
        for partial in openPartials {
            let distance = midi(partial) - note
            if distance >= 0, distance <= 6, best == nil || distance < best! {
                best = distance
            }
        }
        return best.flatMap { valvesBySemitone[$0] }
    }

    func testEveryFingeringMatchesTheInstrument() {
        for note in Note.all {
            guard let expected = expectedFingering(note.name) else {
                return XCTFail("\(note.name) has no three-valve fingering and should not be in the table")
            }
            XCTAssertEqual(
                note.fingering, expected,
                "\(note.name) is listed as \(note.fingering) but physics says \(expected)"
            )
        }
    }

    /// The specific rows that were wrong, pinned by name so a regression names
    /// itself rather than showing up as a generic mismatch.
    func testThePreviouslyWrongRows() {
        let expected = [
            "F#3": "1+2+3", "Gb3": "1+2+3", "G3": "1+3", "Ab3": "2+3",
            "C#4": "1+2+3", "Db4": "1+2+3"
        ]
        for (name, fingering) in expected {
            XCTAssertEqual(Note.named(name)?.fingering, fingering, "\(name)")
        }
    }

    /// F3 needs seven semitones below the C4 partial and three valves reach six.
    /// It sits in the gap between the fundamental and the second partial.
    func testF3IsNotInTheTable() {
        XCTAssertNil(Note.named("F3"))
        XCTAssertNil(expectedFingering("F3"), "F3 should be underivable, not merely absent")
        XCTAssertEqual(Note.selectable.first?.name, "F#3", "the range now starts at F#3")
    }

    /// The mellophone shares its chart with the trumpet, which is what makes the
    /// app usable by a trumpet player reading their own part.
    func testMatchesThePublishedTrumpetChart() {
        // Michael Droste / TrumpetStudio.com, read from the chart itself.
        let published = [
            "F#3": "1+2+3", "G3": "1+3", "Ab3": "2+3", "A3": "1+2", "Bb3": "1", "B3": "2",
            "C4": "Open", "C#4": "1+2+3", "D4": "1+3", "Eb4": "2+3", "E4": "1+2", "F4": "1",
            "F#4": "2", "G4": "Open", "Ab4": "2+3", "A4": "1+2", "Bb4": "1", "B4": "2",
            "C5": "Open", "C#5": "1+2"
        ]
        for (name, fingering) in published {
            XCTAssertEqual(Note.named(name)?.fingering, fingering, "\(name) against the published chart")
        }
    }

    /// C# is 1+2+3 low and 1+2 an octave up, because they come off different
    /// partials. Using one value for both is how the original error arose.
    func testCSharpDiffersBetweenOctaves() {
        XCTAssertEqual(Note.named("C#4")?.fingering, "1+2+3")
        XCTAssertEqual(Note.named("C#5")?.fingering, "1+2")
    }
}
