import CoreGraphics
import XCTest
@testable import Mellophone

/// A part printed in bass clef (#73), the way a tuba or a bass clef euphonium
/// gets its music.
///
/// What is real here, said once:
/// - `bass-clef.pdf` is OUR chart, engraved by MuseScore 4 from
///   `bass-clef.musicxml`, written for this test: the tuba's whole span, ledger
///   lines both ways, notes that take their flat or sharp from the key, and two
///   key changes. The answer is the MusicXML itself, parsed here, so no
///   expected pitch is typed in by hand.
/// - `bass-clef-picture.pdf` is that page drawn at 450 ppi into an image only
///   PDF, the shape of an ePrint. Committed, so the web port (#58) is held to
///   the same picture by `scripts/check-score.js`. The vector read is its
///   answer.
/// - Measured on 2026-11-06, before any change: the vector page already read
///   every note right, and the picture read every note as treble (Bb1 as G3,
///   a sixth and an octave off) with the key gone, and no warning.
final class BassClefChartTests: XCTestCase {

    /// The F clef anchors the staff on F3 and the key signature is read in
    /// bass positions: every pitch, in order, as MuseScore was told it.
    func testTheEngravedPageReadsEveryNoteAsWritten() throws {
        let score = try ScoreImporter.readOrThrow(url: fixture("bass-clef", "pdf"))
        let read = score.events.filter { !$0.isRest }.map(\.writtenName)
        XCTAssertEqual(read, try writtenPitches())
        XCTAssertEqual(score.keySignature, -2, "two flats at the head")
        XCTAssertEqual(score.suspectMeasures, [])
    }

    /// The same page as a picture reads as its vectors do: the F clef is
    /// found from its shape, so nothing reads as treble.
    func testThePictureReadsAsTheEngravedPageDoes() throws {
        let vector = try ScoreImporter.readOrThrow(url: fixture("bass-clef", "pdf"))
        let picture = try ScoreImporter.readOrThrow(url: fixture("bass-clef-picture", "pdf"))
        XCTAssertEqual(notes(picture), notes(vector))
        XCTAssertEqual(picture.keySignature, vector.keySignature)
        XCTAssertEqual(picture.suspectMeasures, [])
    }

    /// A last line holding one bar is found on a picture page (#89). It is
    /// 15% of the page wide and the staff finder's floor was 20%, so bar 12
    /// was dropped and nothing said so: measured 2026-11-06, two lines found
    /// where the engraved page has three.
    func testAShortLastLineIsFoundOnAPicture() throws {
        let vector = try ScoreImporter.readOrThrow(url: fixture("bass-clef", "pdf"))
        let picture = try ScoreImporter.readOrThrow(url: fixture("bass-clef-picture", "pdf"))
        XCTAssertEqual(picture.systems.count, 3)
        XCTAssertEqual(picture.systems.last?.bars.map(\.measure), vector.systems.last?.bars.map(\.measure))
        XCTAssertEqual(picture.events.last?.writtenName, "Ab2")
    }

    /// A treble chart drawn as a picture still finds a G clef and nothing
    /// else: the F clef's test is the two dots either side of the F line, and
    /// a treble page has none.
    func testATreblePictureStillReadsAsTreble() throws {
        let vector = try ScoreImporter.readOrThrow(url: fixture("repeats", "pdf"))
        let picture = try ScoreImporter.readOrThrow(url: fixture("repeats-picture", "pdf"))
        XCTAssertEqual(notes(picture), notes(vector))
    }

    // MARK: - The chart's clef against the horn (#73)

    /// The score says what clef it was printed in, read from the page.
    func testTheScoreKnowsItsClef() throws {
        XCTAssertEqual(try ScoreImporter.readOrThrow(url: fixture("bass-clef", "pdf")).clef, .bass)
        XCTAssertEqual(try ScoreImporter.readOrThrow(url: fixture("bass-clef-picture", "pdf")).clef, .bass)
        XCTAssertEqual(try ScoreImporter.readOrThrow(url: fixture("repeats", "pdf")).clef, .treble)
    }

    /// A tuba part opened on a mellophone plays as printed. Played for the
    /// mellophone it came out a fifth under the page, Bb1 as Eb1, which is
    /// no horn's part at all.
    @MainActor
    func testABassChartOnATrebleHornPlaysAsPrinted() throws {
        let model = PartModel()
        model.adopt(try ScoreImporter.readOrThrow(url: fixture("bass-clef", "pdf")))
        for horn in [Instrument.mellophone, .frenchHorn, .trumpet, .euphonium, .tuba, .euphoniumBass] {
            let timeline = try XCTUnwrap(model.prepare(bpm: 96, instrument: horn))
            let bb1 = try XCTUnwrap(timeline.entries.first { $0.event.writtenName == "Bb1" }?.frequency)
            XCTAssertEqual(timeline.rendered(bb1), bb1, accuracy: 0.001, "\(horn) plays Bb1 as printed")
            XCTAssertGreaterThan(timeline.brightnessFloor, 0, "\(horn): a tuba's Bb1 still reaches a phone speaker")
        }
    }

    /// A treble part still plays at the pitch the treble horn makes: the
    /// mellophone's fifth under the page is untouched.
    @MainActor
    func testATrebleChartOnATrebleHornIsUnchanged() throws {
        let model = PartModel()
        model.adopt(try ScoreImporter.readOrThrow(url: fixture("repeats", "pdf")))
        let timeline = try XCTUnwrap(model.prepare(bpm: 96, instrument: .mellophone))
        let written = try XCTUnwrap(timeline.entries.compactMap(\.frequency).first)
        XCTAssertEqual(timeline.rendered(written), Instrument.mellophone.sounding(written), accuracy: 0.001)
        XCTAssertTrue(model.readsClef(.mellophone))
        XCTAssertNil(model.clefNote(for: .mellophone))
    }

    /// Which horns read the part, and the one line that says so when the
    /// selected one does not. No valves are shown for a part the horn does
    /// not read: a mellophone's valves for a concert pitch teach the wrong
    /// note.
    @MainActor
    func testTheScreenSaysWhichHornsReadThePart() throws {
        let bass = PartModel()
        bass.adopt(try ScoreImporter.readOrThrow(url: fixture("bass-clef", "pdf")))
        XCTAssertTrue(bass.readsClef(.tuba))
        XCTAssertTrue(bass.readsClef(.euphoniumBass))
        XCTAssertFalse(bass.readsClef(.mellophone))
        XCTAssertFalse(bass.readsClef(.euphonium))
        XCTAssertNil(bass.clefNote(for: .tuba))
        XCTAssertEqual(bass.clefNote(for: .mellophone),
                       "This part is in bass clef, for the tuba or Euphonium B.C. It plays as printed, with no valves shown. Change the instrument at the top of this screen to see them.")
        let treble = PartModel()
        treble.adopt(try ScoreImporter.readOrThrow(url: fixture("repeats", "pdf")))
        XCTAssertFalse(treble.readsClef(.tuba))
        XCTAssertEqual(treble.clefNote(for: .tuba),
                       "This part is in treble clef, for the mellophone, horn, trumpet or Euphonium T.C. It plays as printed, with no valves shown. Change the instrument at the top of this screen to see them.")
    }

    // MARK: - Helpers

    /// Every pitched note in `bass-clef.musicxml`, spelled the reader's way.
    private func writtenPitches() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bass-clef.musicxml")
        let xml = try String(contentsOf: url, encoding: .utf8)
        let pitch = #/<pitch><step>([A-G])</step>(?:<alter>(-?\d)</alter>)?<octave>(\d)</octave></pitch>/#
        let names = xml.matches(of: pitch).map { match -> String in
            let alter = match.output.2.map { Int($0)! } ?? 0
            return "\(match.output.1)\(alter < 0 ? "b" : alter > 0 ? "#" : "")\(match.output.3)"
        }
        XCTAssertEqual(names.count, 42, "the fixture's 42 notes")
        return names
    }

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext), "\(name).\(ext) is not in the test bundle")
    }

    private func notes(_ score: Score) -> [Int: [String]] {
        var bars: [Int: [String]] = [:]
        for event in score.events {
            let beats = (event.durationBeats * 1000).rounded() / 1000
            let length = beats == beats.rounded() ? "\(Int(beats))" : "\(beats)"
            bars[event.measure, default: []].append(event.isRest ? "rest \(length)" : "\(event.writtenName) \(length)")
        }
        return bars
    }
}
