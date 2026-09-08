import XCTest
import CoreGraphics
@testable import Mellophone

/// The one test that reads a real engraved PDF end to end.
///
/// Everything else in this suite works on hand-built geometry, which proves the
/// logic but cannot prove that a genuine notation export parses at all. The
/// difference is not academic: every serious bug in this reader so far came
/// from a real file disagreeing with an assumption, and none of them would have
/// been caught by a rectangle someone typed.
///
/// The fixture is OURS, authored in MuseScore for this purpose. Sam's charts are
/// copyrighted arrangements, this repo is public, and the app declares
/// DOES_NOT_USE_THIRD_PARTY_CONTENT. His charts live in `Fixtures/local/`,
/// which is gitignored, and are used for manual spot checks only.
final class ScoreImportEndToEndTests: XCTestCase {

    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "one-octave-f-major", withExtension: "pdf"),
                      "the fixture is not in the test bundle: check the resources phase in project.yml")
    }

    /// One octave up and back down, one note per beat, in F major.
    func testReadsTheAuthoredScaleExactly() throws {
        let score = try ScoreImporter.readOrThrow(url: fixture())
        XCTAssertEqual(score.keySignature, -1, "F major is one flat")
        XCTAssertEqual(score.timeSignature.beats, 4)
        XCTAssertEqual(score.timeSignature.unit, 4)
        XCTAssertEqual(score.voiceCount, 1)
        XCTAssertEqual(score.events.compactMap { $0.note?.name },
                       ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5",
                        "F5", "E5", "D5", "C5", "Bb4", "A4", "G4", "F4"])
        XCTAssertTrue(score.events.allSatisfy { $0.durationBeats == 1.0 },
                      "durations: \(score.events.map(\.durationBeats))")
    }

    /// Every measure sums, so nothing is suspect. If this fails the reader is
    /// wrong somewhere and the validator is doing its job.
    func testNothingIsFlaggedOnAFileWeAuthored() throws {
        let score = try ScoreImporter.readOrThrow(url: fixture())
        XCTAssertTrue(score.suspectMeasures.isEmpty,
                      "suspect: \(score.suspectMeasures.sorted())")
        XCTAssertTrue(score.unreadableSymbols.isEmpty,
                      "unreadable: \(score.unreadableSymbols.map { String(format: "U+%04X", $0) })")
    }

    /// A PDF with no music font must be refused PLAINLY rather than producing a
    /// bad transcription or an empty score with no explanation. Two music PDFs
    /// on the build machine are vector flattened and would otherwise read as
    /// nothing at all, and "this PDF has no readable notation in it" is the only
    /// honest thing to say about them.
    func testAPDFWithNoMusicFontIsRefused() throws {
        let plain = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).pdf")
        try makePlainPDF(at: plain)
        defer { try? FileManager.default.removeItem(at: plain) }

        XCTAssertThrowsError(try ScoreImporter.readOrThrow(url: plain)) { error in
            XCTAssertEqual(error as? ImportError, .noReadableNotation)
        }
        XCTAssertNil(ScoreImporter.read(url: plain), "the non-throwing form returns nil")
    }

    /// A file that is not a PDF at all fails differently, and has to, because
    /// "could not open this file" and "no notation in it" send someone to
    /// different next steps.
    func testAFileThatIsNotAPDFIsRefusedDifferently() throws {
        let junk = FileManager.default.temporaryDirectory
            .appendingPathComponent("junk-\(UUID().uuidString).pdf")
        try Data("not a pdf".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }

        XCTAssertThrowsError(try ScoreImporter.readOrThrow(url: junk)) { error in
            XCTAssertEqual(error as? ImportError, .cannotOpenFile)
        }
    }

    /// A one page PDF with text in a normal font and no music font anywhere.
    private func makePlainPDF(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // Five horizontal rules, so the failure cannot be "there was nothing on
        // the page": this looks like a staff and still has no notation on it.
        for i in 0..<5 {
            context.fill(CGRect(x: 20, y: 100 + Double(i) * 5, width: 160, height: 0.7))
        }
        context.endPDFPage()
        context.closePDF()
    }
}
