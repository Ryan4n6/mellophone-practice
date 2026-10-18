import XCTest
import CoreGraphics
@testable import Mellophone

/// What the chart reader got wrong on Sam's real charts, and the proof it no
/// longer does (#39).
///
/// What is real here, said once:
/// - `reader-traps.pdf` is a real engraved PDF, exported by MuseScore 4 from a
///   MusicXML file written for this test. It is OURS and in git. It holds a
///   flagged chord, both kinds of triplet, a second, a key change mid-line and
///   two ties, and it is read end to end like any chart a student opens.
/// - The stem test builds its geometry by hand, because MuseScore did not draw
///   a stem as tall as the staff anywhere in the fixture. The positions are
///   the ones measured on Sam's charts.
/// - The last two tests read Sam's charts themselves, and only on a machine
///   that has them: they are copyrighted, gitignored and never in a build, so
///   a clone skips them. They are the only tests here that have seen a chart
///   a director actually handed out.
final class ChartReaderTrapsTests: XCTestCase {

    // MARK: - The fixture, bar by bar

    private struct Expected: Equatable, CustomStringConvertible {
        let bar: Int, voice: Int, name: String, beats: Double, tied: Bool
        var description: String { "bar \(bar) v\(voice) \(name)/\(beats)\(tied ? " tied" : "")" }
    }

    private func read(_ score: Score) -> [Expected] {
        score.events
            .sorted { ($0.measure, $0.voice, $0.onsetBeats) < ($1.measure, $1.voice, $1.onsetBeats) }
            .map { Expected(bar: $0.measure, voice: $0.voice, name: $0.isRest ? "r" : $0.writtenName,
                            beats: ($0.durationBeats * 1_000_000).rounded() / 1_000_000, tied: $0.tiedFromPrevious) }
    }

    /// Every bar of the fixture, against the MusicXML it was engraved from.
    func testEveryTrapReadsAsWritten() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader-traps", withExtension: "pdf"),
                                "the fixture is not in the test bundle")
        let score = try ScoreImporter.readOrThrow(url: url)
        let third = (1.0 / 3 * 1_000_000).rounded() / 1_000_000
        let twoThirds = (2.0 / 3 * 1_000_000).rounded() / 1_000_000
        func e(_ bar: Int, _ name: String, _ beats: Double, voice: Int = 0, tied: Bool = false) -> Expected {
            Expected(bar: bar, voice: voice, name: name, beats: beats, tied: tied)
        }
        let expected = [
            // A flag on a chord belongs to both notes of it.
            e(1, "C5", 0.5), e(1, "r", 0.5), e(1, "C5", 0.5), e(1, "r", 0.5), e(1, "F4", 2),
            e(1, "A4", 0.5, voice: 1), e(1, "F4", 0.5, voice: 1),
            // Beamed triplet eighths, a quarter, a bracketed quarter triplet.
            e(2, "G4", third), e(2, "A4", third), e(2, "Bb4", third), e(2, "C5", 1),
            e(2, "D5", twoThirds), e(2, "C5", twoThirds), e(2, "Bb4", twoThirds),
            // A second is a chord, not two notes in a row.
            e(3, "F5", 1), e(3, "F5", 1), e(3, "C5", 2),
            e(3, "E5", 1, voice: 1), e(3, "E5", 1, voice: 1),
            // Three flats from here, in the middle of the line.
            e(4, "Eb5", 1), e(4, "Ab4", 1), e(4, "D5", 1), e(4, "Bb4", 1),
            // Tied across the line break.
            e(5, "G4", 4), e(6, "G4", 4, tied: true),
            // The tied note keeps its natural against the key.
            e(7, "r", 2), e(7, "A4", 2),
            e(8, "A4", 1, tied: true), e(8, "r", 1), e(8, "r", 2),
            e(9, "C5", 4), e(9, "Ab4", 4, voice: 1),
        ]
        let got = read(score)
        XCTAssertEqual(got, expected)
        if got != expected {
            for (index, pair) in zip(got, expected).enumerated() where pair.0 != pair.1 {
                print("TRAPS first difference at \(index): read \(pair.0), page says \(pair.1)")
                break
            }
        }
        XCTAssertTrue(score.suspectMeasures.isEmpty, "suspect: \(score.suspectMeasures.sorted())")
    }

    // MARK: - Tempo marks (#41)

    /// The fixture's three marks, each on the bar MuseScore printed it over:
    /// the "Faster" one in the middle of a line and the dotted one 1.5
    /// quarters long, so it is 120 quarters a minute and not 80.
    func testEveryTempoMarkIsReadOnTheBarItIsPrintedOver() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader-traps", withExtension: "pdf"))
        let score = try ScoreImporter.readOrThrow(url: url)
        XCTAssertEqual(score.tempos, [
            TempoChange(measure: 1, onsetBeats: 0, printed: 96, noteQuarters: 1),
            TempoChange(measure: 4, onsetBeats: 12, printed: 132, noteQuarters: 1),
            TempoChange(measure: 7, onsetBeats: 24, printed: 80, noteQuarters: 1.5),
        ])

        // And the chart plays at them, end to end: three bars at 96, three
        // at 132, then 120.
        let timeline = PartTimeline(score: score, voice: .line(0), measures: 1...9, bpm: 96)
        let start = Dictionary(timeline.measures.map { ($0.number, $0.start) }) { first, _ in first }
        let atBar4 = 12 * 60.0 / 96, atBar7 = atBar4 + 12 * 60.0 / 132
        XCTAssertEqual(try XCTUnwrap(start[4]), atBar4, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(start[7]), atBar7, accuracy: 1e-6)
        XCTAssertEqual(timeline.duration, atBar7 + 12 * 60.0 / 120, accuracy: 1e-6)
    }

    // MARK: - A stem as tall as the staff

    private let lineYs = [360.52, 365.48, 370.44, 375.40, 380.36]
    private let halfSpace = 2.48
    private func y(step: Double) -> Double { lineYs[0] + step * halfSpace }
    private func head(x: Double, step: Double) -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE0A4, x: x, y: y(step: step), size: 19.84, font: "Leland")
    }
    /// A vertical line from the bottom line to the top line at `x`: a barline,
    /// or a stem that happens to be exactly that long.
    private func fullHeight(at x: Double) -> PlacedPath {
        PlacedPath(vertices: [], filled: false,
                   bounds: CGRect(x: x, y: lineYs[0], width: 0, height: lineYs[4] - lineYs[0]))
    }

    /// A note on the bottom line with its stem up, and one on the top line
    /// with its stem down, each with a stem exactly as tall as the staff. All
    /// five of PEAK's extra bars were one of these read as a barline. The two
    /// notes beside the real barlines sit at the nearest distances measured
    /// on the charts, 4.13 half-spaces before one and 2.67 after another, and
    /// those lines still have to be barlines.
    func testAStemAsTallAsTheStaffIsNotABarline() {
        let up = head(x: 100, step: 0), middle = head(x: 130, step: 4), down = head(x: 160, step: 8)
        let afterBar = head(x: 200 + 2.67 * halfSpace, step: 8)
        let beforeBar = head(x: 300 - 4.13 * halfSpace, step: 0)
        let last = head(x: 330, step: 4)
        let staff = lineYs.map {
            PlacedPath(vertices: [], filled: true, bounds: CGRect(x: 42.5, y: $0 - 0.35, width: 510, height: 0.7))
        }
        let clef = PlacedGlyph(scalar: 0xE050, x: 46, y: y(step: 2), size: 19.84, font: "Leland")
        let score = ScoreBuilder.build(
            pages: [PageGeometry(glyphs: [clef, up, middle, down, afterBar, beforeBar, last],
                                 paths: staff + [fullHeight(at: up.x + 2.5 * halfSpace),
                                                 fullHeight(at: down.x + 0.13 * halfSpace),
                                                 fullHeight(at: 200), fullHeight(at: 300)])],
            font: MusicFontTable.forFont("Leland")!)
        XCTAssertEqual(score.events.map(\.measure), [1, 1, 1, 2, 2, 3],
                       "\(score.events.map { "\($0.writtenName) in \($0.measure)" })")
    }

    // MARK: - Sam's charts, where they exist

    private func local(_ name: String) throws -> Score {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/local/\(name)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) is not on this machine; the fixture test above still ran")
        }
        return try ScoreImporter.readOrThrow(url: url)
    }

    private func names(_ score: Score, bar: Int) -> [String] {
        score.events.filter { $0.measure == bar && !$0.isRest }
            .sorted { ($0.onsetBeats, $0.voice) < ($1.onsetBeats, $1.voice) }.map(\.writtenName)
    }

    /// PEAK, checked against the printed page on 2026-10-18. The numbers are
    /// what the page prints, so a bar here is the bar a student asks for.
    func testPEAKCountsItsBarsLikeThePageAndReadsTheBarsItGotWrong() throws {
        let score = try local("PEAK mello.pdf")
        XCTAssertEqual(score.events.map(\.measure).max(), 251, "the page ends at bar 251; this read 256 before #39")
        XCTAssertTrue(score.suspectMeasures.isEmpty, "suspect: \(score.suspectMeasures.sorted())")
        // The key goes to one flat at bar 28, mid-line, so these Ds are D.
        XCTAssertEqual(names(score, bar: 34), ["D4", "Ab4"])
        XCTAssertEqual(names(score, bar: 35), ["D4", "A4"])
        // An A tied from an A flat is an A flat.
        let tied = try XCTUnwrap(score.events.first { $0.measure == 51 && !$0.isRest })
        XCTAssertEqual(tied.writtenName, "Ab4")
        XCTAssertTrue(tied.tiedFromPrevious)
        // Bars that open a printed line, by what is printed in them.
        XCTAssertEqual(names(score, bar: 163).first, "C4")
        XCTAssertEqual(names(score, bar: 184), ["D5", "D5"])
        XCTAssertEqual(names(score, bar: 237), ["A4"])
        XCTAssertEqual(score.events.filter { (247...251).contains($0.measure) && !$0.isRest }.map(\.tiedFromPrevious),
                       [false, true, true, true, true], "C5 held from 247 to 251")
    }

    /// Every tempo PEAK prints, read off the rendered pages on 2026-10-18,
    /// all of them quarter notes. 104's "♩ = 72" sits 0.81 half-spaces BEFORE
    /// the barline it follows and 106's is pushed past its multi-bar rest by
    /// "Part 2 A Tempo": both landed in the wrong bar on the way here (#41).
    func testPEAKPlaysAtEveryTempoItPrints() throws {
        let score = try local("PEAK mello.pdf")
        XCTAssertEqual(score.tempos.map { [$0.measure, $0.printed] },
                       [[1, 120], [27, 160], [101, 144], [102, 132], [103, 112], [104, 72],
                        [106, 144], [154, 120], [159, 130], [161, 140], [163, 152], [205, 160]])
        XCTAssertTrue(score.tempos.allSatisfy { $0.noteQuarters == 1 })
    }

    func testFloridaPlaysAtItsPrintedTempo() throws {
        let score = try local("Florida Fight Song (Orange and Blue)-Horn in F.pdf")
        XCTAssertEqual(score.tempos, [TempoChange(measure: 1, onsetBeats: 0, printed: 158, noteQuarters: 1)])
    }

    /// The Florida chart, checked against the printed page on 2026-10-18.
    func testFloridaKeepsItsNarrowBarsAndReadsItsChordsWhole() throws {
        let score = try local("Florida Fight Song (Orange and Blue)-Horn in F.pdf")
        XCTAssertEqual(score.events.map(\.measure).max(), 42)
        XCTAssertTrue(score.suspectMeasures.isEmpty, "suspect: \(score.suspectMeasures.sorted())")
        // The last bar of lines 1 and 3, dropped before #39.
        XCTAssertEqual(names(score, bar: 14), ["Bb4", "G4"])
        XCTAssertEqual(names(score, bar: 35), ["B4", "F4"])
        // Four eighth-note chords, cut in two at a stem before #39.
        XCTAssertEqual(names(score, bar: 18), ["A4", "F#4", "F#4", "D4", "G4", "E4", "A4", "F#4"])
        // Both notes of a flagged chord are eighths.
        XCTAssertEqual(score.events.filter { $0.measure == 7 }.sorted { ($0.voice, $0.onsetBeats) < ($1.voice, $1.onsetBeats) }
                        .map(\.durationBeats), [0.5, 1, 0.5, 0.5, 1, 0.5])
        XCTAssertEqual(score.events.filter { $0.measure == 38 && $0.onsetBeats == score.events.first { $0.measure == 38 }!.onsetBeats }
                        .map(\.tiedFromPrevious), [true, true], "the tied chord into bar 38")
    }
}
