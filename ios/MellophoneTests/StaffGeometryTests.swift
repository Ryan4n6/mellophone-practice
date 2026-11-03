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
        for note in Instrument.mellophone.notes {
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
        for note in Instrument.mellophone.notes {
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

    // MARK: - Bass clef (#72)

    /// In bass clef the five lines are, top to bottom, A3 F3 D3 B2 G2, on the
    /// same five drawn lines as the treble staff.
    func testBassLineNotesLandOnTheirLines() throws {
        let expected: [(String, CGFloat)] = [("A3", 60), ("F3", 80), ("D3", 100), ("B2", 120), ("G2", 140)]
        for (name, lineY) in expected {
            XCTAssertEqual(StaffGeometry.y(for: try XCTUnwrap(Note.named(name)), clef: .bass), lineY, name)
            XCTAssertTrue(StaffGeometry.staffLineYs.contains(lineY))
        }
        // And the treble staff is what it was.
        XCTAssertEqual(StaffGeometry.layout(.treble).height, StaffGeometry.height)
        XCTAssertEqual(StaffGeometry.y(for: try XCTUnwrap(Note.named("G4")), clef: .treble), 120)
    }

    /// Every note either bass horn is shown is inside the drawing with room
    /// for its head and its accidental, and every one off the staff has a
    /// ledger line under or over it: a tuba's E1 hangs below four, a bass
    /// clef euphonium's Bb4 sits on the fourth above.
    func testEveryBassHornNoteFitsAndHasItsLedgers() throws {
        let layout = StaffGeometry.layout(.bass)
        for instrument in [Instrument.tuba, .euphoniumBass] {
            for note in instrument.notes {
                let y = StaffGeometry.y(for: note, clef: .bass)
                XCTAssertGreaterThanOrEqual(y - 32, layout.top, "\(note.name): its flat's stem is cut off at the top")
                XCTAssertLessThanOrEqual(y + 15, layout.top + layout.height, "\(note.name) is off the bottom")
                // A line every 20 from the staff out to the note: under the
                // staff every line at or above the note's y, over it every
                // line at or below.
                for line in stride(from: CGFloat(160), through: y, by: 20) {
                    XCTAssertTrue(layout.ledgersBelow.contains(line), "\(note.name) needs a ledger at \(line)")
                }
                for line in stride(from: CGFloat(40), through: y, by: -20) {
                    XCTAssertTrue(layout.ledgersAbove.contains(line), "\(note.name) needs a ledger at \(line)")
                }
            }
        }
        XCTAssertEqual(StaffGeometry.y(for: try XCTUnwrap(Note.named("E1")), clef: .bass), 230)
        XCTAssertEqual(StaffGeometry.y(for: try XCTUnwrap(Note.named("F1")), clef: .bass), 220, "F1 sits on the fourth ledger")
        XCTAssertEqual(StaffGeometry.y(for: try XCTUnwrap(Note.named("Bb4")), clef: .bass), -20)
    }

    /// The clef is where an F clef has to be: its two dots either side of the
    /// F line, y = 80, and inside the top and bottom of the staff.
    func testTheBassClefSitsOnTheFLine() {
        let box = BassClef.path.boundingRect
        XCTAssertEqual(box.minY, 59, accuracy: 0.5, "the top of the clef at the top line")
        XCTAssertGreaterThan(box.maxY, 100, "the tail reaches below the middle line")
        XCTAssertLessThan(box.maxY, 140)
        // The two dots: the rightmost ink, one either side of the F line.
        let dotsColumn = box.maxX - 4.4
        XCTAssertTrue(BassClef.path.contains(CGPoint(x: dotsColumn, y: 70)), "the upper dot is in the A3 to F3 space")
        XCTAssertTrue(BassClef.path.contains(CGPoint(x: dotsColumn, y: 90)), "the lower dot is in the F3 to D3 space")
        XCTAssertFalse(BassClef.path.contains(CGPoint(x: dotsColumn, y: 80)), "and nothing on the line between them")
    }
}

/// Guards on the data itself, which is generated from index.html by
/// scripts/sync-note-data.py.
final class NoteDataTests: XCTestCase {

    func testTableIsComplete() {
        // 36, not 37: F3 was removed in #9 because three valves reach six
        // semitones and F3 needs seven. The count is pinned so an accidental
        // deletion during a data edit shows up as a failure.
        XCTAssertEqual(Instrument.mellophone.notes.count, 36)
        // And the rows under the treble staff for the bass horns (#72), E1 to
        // F3, thirty of them, so 66.
        XCTAssertEqual(Note.all.count, 66)
        XCTAssertEqual(Scale.all.count, 10)
    }

    /// `selectable` drops a flat only when a sharp spelling exists at the same
    /// pitch, which is the rule `NATURAL_NOTES` uses in the web version.
    /// The default practice range is the working range, not the instrument's
    /// full span. F#3 to C6 is what is expected of a drum corps lead player.
    func testDefaultRangeIsTheWorkingRange() {
        let range = Instrument.mellophone.range(from: "C4", to: "G5")
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
        // "" for the rows only a bass horn plays (#72): the stored column is
        // the mellophone's chart, and the mellophone cannot play them.
        let allowed: Set<String> = ["Open", "1", "2", "3", "1+2", "1+3", "2+3", "1+2+3", ""]
        for note in Note.all {
            XCTAssertTrue(allowed.contains(note.fingering), "\(note.name) has fingering \"\(note.fingering)\"")
        }
    }

    func testEveryScaleNoteResolves() {
        for scale in Scale.all {
            XCTAssertEqual(scale.notes.count, scale.noteNames.count, "\(scale.name) has an unresolvable note")
        }
    }

    func testRangeIsInclusiveAndOrderIndependent() {
        let up = Instrument.mellophone.range(from: "C4", to: "C5")
        let down = Instrument.mellophone.range(from: "C5", to: "C4")
        XCTAssertEqual(up.map(\.name), down.map(\.name))
        XCTAssertEqual(up.first?.name, "C4")
        XCTAssertEqual(up.last?.name, "C5")
    }
}
