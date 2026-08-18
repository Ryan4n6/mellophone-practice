import XCTest
@testable import Mellophone

/// The staff conversion is the thing `index.html` gets wrong (issue #8), so it
/// is pinned here against the staff lines rather than against the formula.
final class StaffGeometryTests: XCTestCase {

    /// In treble clef the five lines are, top to bottom, F5 D5 B4 G4 E4. Each
    /// has to land exactly on the y its own line is drawn at.
    func testLineNotesLandOnTheirLines() throws {
        let expected: [(String, CGFloat)] = [
            ("F5", 60), ("D5", 80), ("B4", 100), ("G4", 120), ("E4", 140)
        ]
        for (name, lineY) in expected {
            let note = try XCTUnwrap(Note.named(name))
            XCTAssertEqual(StaffGeometry.y(for: note), lineY, "\(name) should sit on the line at \(lineY)")
            XCTAssertTrue(StaffGeometry.staffLineYs.contains(lineY))
        }
    }

    /// Space notes sit exactly halfway between their neighbouring lines.
    func testSpaceNotesSitBetweenLines() throws {
        let expected: [(String, CGFloat)] = [
            ("E5", 70), ("C5", 90), ("A4", 110), ("F4", 130)
        ]
        for (name, y) in expected {
            let note = try XCTUnwrap(Note.named(name))
            XCTAssertEqual(StaffGeometry.y(for: note), y, "\(name)")
        }
    }

    /// The web version's formula, kept here as an explicit regression guard so
    /// nobody "restores fidelity to index.html" and silently reintroduces it.
    func testDoesNotUseTheWebVersionsFormula() {
        for note in Note.all {
            let web = CGFloat(note.staffPosition) * 0.5 + 30
            let ours = StaffGeometry.y(for: note)
            // A5 is the single note where the two formulas agree.
            if note.name == "A5" || note.name == "Ab5" {
                XCTAssertEqual(web, ours)
            } else {
                XCTAssertNotEqual(web, ours, "\(note.name) must not use the index.html conversion")
            }
        }
    }

    /// Every note in the range has to be inside the drawing area, including F3,
    /// which needs a third ledger line below the staff that the web version
    /// does not have.
    ///
    /// The bottom note is F#3, not F3. F3 was removed in #9 because three valves
    /// reach six semitones and it needs seven. F#3 sits on the same line with a
    /// sharp, so the third ledger is still required.
    ///
    /// `throws` and a plain `XCTUnwrap` rather than `try!`: a data change that
    /// removes a note should FAIL this test, not crash the process and abort
    /// every other test in the suite, which is exactly what F3's removal did.
    func testWholeRangeFitsTheCanvas() throws {
        for note in Note.all {
            let y = StaffGeometry.y(for: note)
            XCTAssertGreaterThanOrEqual(y, 20)
            XCTAssertLessThanOrEqual(y, StaffGeometry.height - 15, "\(note.name) at \(y) is off the bottom")
        }
        let lowest = try XCTUnwrap(Note.named("F#3"))
        XCTAssertEqual(StaffGeometry.y(for: lowest), 200)
        XCTAssertTrue(StaffGeometry.ledgerYsBelow.contains(200), "F#3 needs a third ledger line")
    }

    /// Enharmonic pairs deliberately sit on DIFFERENT lines: F#3 on the F, Gb3
    /// on the G. That is why the table has separate rows for them.
    func testEnharmonicsAreSpelledOnDifferentLines() throws {
        let sharp = try XCTUnwrap(Note.named("F#3"))
        let flat = try XCTUnwrap(Note.named("Gb3"))
        XCTAssertEqual(sharp.frequency, flat.frequency)
        XCTAssertNotEqual(StaffGeometry.y(for: sharp), StaffGeometry.y(for: flat))
    }
}

/// Guards on the data itself, which is generated from index.html by
/// scripts/sync-note-data.py.
final class NoteDataTests: XCTestCase {

    func testTableIsComplete() {
        // 36, not 37: F3 was removed in #9 because three valves reach six
        // semitones and F3 needs seven. The count is pinned so an accidental
        // deletion during a data edit shows up as a failure.
        XCTAssertEqual(Note.all.count, 36)
        XCTAssertEqual(Scale.all.count, 10)
    }

    /// `selectable` drops a flat only when a sharp spelling exists at the same
    /// pitch, which is the rule `NATURAL_NOTES` uses in the web version.
    /// The default practice range is the working range, not the instrument's
    /// full span. F#3 to C6 is what is expected of a drum corps lead player.
    func testDefaultRangeIsTheWorkingRange() {
        let range = Note.range(from: "C4", to: "G5")
        XCTAssertEqual(range.first?.name, "C4")
        XCTAssertEqual(range.last?.name, "G5")
        XCTAssertGreaterThan(range.count, 12, "a usable drill pool")
    }

    func testSelectableDropsRedundantFlats() {
        XCTAssertNil(Note.selectable.first { $0.name == "Gb3" })   // F#3 covers it
        XCTAssertNotNil(Note.selectable.first { $0.name == "Ab3" }) // no G#3 in the table
        XCTAssertNotNil(Note.selectable.first { $0.name == "F#3" })
    }

    /// Fingering strings double as an equality key for the harmonic-series card,
    /// so they have to be written consistently.
    func testFingeringStringsAreCanonical() {
        let allowed: Set<String> = ["Open", "1", "2", "3", "1+2", "1+3", "2+3", "1+2+3"]
        for note in Note.all {
            XCTAssertTrue(allowed.contains(note.fingering), "\(note.name) has fingering \"\(note.fingering)\"")
        }
    }

    func testSameFingeringFindsTheHarmonicSeries() throws {
        let c4 = try XCTUnwrap(Note.named("C4"))
        let names = Set(c4.sameFingering.map(\.name))
        // The open harmonic series: C4, G4, C5, E5, G5, C6. That is the
        // fundamental and its 3rd, 4th, 5th, 6th and 8th partials, which is
        // exactly the point of the card: six notes, no valves, all separated by
        // the player's ear.
        XCTAssertEqual(names, ["G4", "C5", "E5", "G5", "C6"])
    }

    func testEveryScaleNoteResolves() {
        for scale in Scale.all {
            XCTAssertEqual(scale.notes.count, scale.noteNames.count, "\(scale.name) has an unresolvable note")
        }
    }

    func testRangeIsInclusiveAndOrderIndependent() {
        let up = Note.range(from: "C4", to: "C5")
        let down = Note.range(from: "C5", to: "C4")
        XCTAssertEqual(up.map(\.name), down.map(\.name))
        XCTAssertEqual(up.first?.name, "C4")
        XCTAssertEqual(up.last?.name, "C5")
    }
}
