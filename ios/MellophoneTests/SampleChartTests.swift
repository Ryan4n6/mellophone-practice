import XCTest
@testable import Mellophone

/// The one chart the app ships (#28), read with the real importer out of the
/// real app bundle.
///
/// Nothing here is hand-built geometry. The PDF is the file a new install
/// opens, MuseScore engraved it from `ios/scripts/sample-chart.musicxml`, and
/// the table below is that source written out again by hand, so the reader is
/// being checked against what was composed and not against itself.
///
/// This test is what found #29. The first reading of this file came back with
/// bars 2 and 13 as quarters, because a beam over four eighths was wider than
/// the reader would accept.
final class SampleChartTests: XCTestCase {

    /// Sixteen bars of 4/4 in written F. "r" is a rest, lengths are in beats.
    private let written: [[(String, Double)]] = [
        [("F4", 1), ("A4", 1), ("C5", 2)],
        [("C5", 0.5), ("D5", 0.5), ("C5", 0.5), ("Bb4", 0.5), ("A4", 1), ("F4", 1)],
        [("G4", 1.5), ("A4", 0.5), ("Bb4", 1), ("G4", 1)],
        [("A4", 3), ("r", 1)],
        [("F4", 1), ("A4", 1), ("C5", 2)],
        [("D5", 0.5), ("E5", 0.5), ("F5", 1), ("E5", 1), ("C5", 1)],
        [("D5", 1.5), ("C5", 0.5), ("B4", 1), ("D5", 1)],
        [("C5", 4)],
        [("r", 4)],
        [("r", 4)],
        [("C5", 1), ("C5", 0.5), ("C5", 0.5), ("D5", 1), ("C5", 1)],
        [("Bb4", 1), ("Bb4", 0.5), ("Bb4", 0.5), ("C5", 1), ("Bb4", 1)],
        [("A4", 0.5), ("Bb4", 0.5), ("C5", 0.5), ("D5", 0.5), ("C5", 1), ("A4", 1)],
        [("G4", 3), ("r", 1)],
        [("A4", 1), ("C5", 1), ("F5", 1), ("E5", 0.5), ("D5", 0.5)],
        [("C5", 1), ("G4", 1), ("F4", 2)],
    ]

    private func sample() throws -> URL {
        try XCTUnwrap(SampleChart.url,
                      "the sample chart is not in the app bundle: check Mellophone/Resources")
    }

    func testTheSampleReadsBackExactlyAsItWasWritten() throws {
        let score = try ScoreImporter.readOrThrow(url: sample())
        XCTAssertEqual(score.keySignature, -1, "one flat")
        XCTAssertEqual(score.timeSignature.beats, 4)
        XCTAssertEqual(score.timeSignature.unit, 4)
        XCTAssertEqual(score.voiceCount, 1)

        let bars = Dictionary(grouping: score.events, by: \.measure)
        XCTAssertEqual(bars.keys.sorted(), Array(1...written.count), "sixteen bars, numbered from one")
        for (index, expected) in written.enumerated() {
            let read = (bars[index + 1] ?? []).sorted { $0.onsetBeats < $1.onsetBeats }
            XCTAssertEqual(read.map { $0.isRest ? "r" : $0.writtenName }, expected.map(\.0),
                           "the notes of bar \(index + 1)")
            XCTAssertEqual(read.map(\.durationBeats), expected.map(\.1),
                           "the lengths in bar \(index + 1)")
        }
    }

    /// A chart we wrote for the reader has no business confusing it. If a bar
    /// here is ever flagged, a new user's first chart opens with a warning on
    /// it.
    func testNothingInTheSampleIsFlagged() throws {
        let score = try ScoreImporter.readOrThrow(url: sample())
        XCTAssertTrue(score.suspectMeasures.isEmpty, "suspect: \(score.suspectMeasures.sorted())")
        XCTAssertTrue(score.unreadableSymbols.isEmpty,
                      "unreadable: \(score.unreadableSymbols.map { String(format: "U+%04X", $0) })")
    }

    /// The sample is for whoever installs the app, on any of the four horns,
    /// so every note in it has to have valves to show.
    func testEveryNoteOfTheSampleHasAFingeringOnEveryInstrument() throws {
        let score = try ScoreImporter.readOrThrow(url: sample())
        for event in score.events where !event.isRest {
            XCTAssertNotNil(event.note, "\(event.writtenName) is outside the app's note table")
            for instrument in Instrument.allCases {
                XCTAssertNotNil(Fingering.value(for: event.writtenName, on: instrument),
                                "\(event.writtenName) has no fingering on \(instrument.displayName)")
            }
        }
    }

    // MARK: - Seeding

    private var scratch: URL!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-\(UUID().uuidString)", isDirectory: true)
        // Its own defaults, so a test can neither see nor set the flag of
        // whoever is running the tests.
        suite = "sample-chart-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        defaults.removePersistentDomain(forName: suite)
    }

    func testAFirstRunPutsTheSampleInTheLibrary() throws {
        let library = ChartLibrary(directory: scratch)
        library.seedSample(from: try sample(), defaults: defaults)
        XCTAssertEqual(library.charts.map(\.title), [SampleChart.name])
        XCTAssertNotNil(ScoreImporter.read(url: try XCTUnwrap(library.charts.first).url),
                        "the copy in the library is a chart the reader can open")
    }

    /// The reason for the flag. A student who takes the sample out has said
    /// they do not want it, and it must not be back on the next launch.
    func testRemovingTheSampleKeepsItRemoved() throws {
        let first = ChartLibrary(directory: scratch)
        first.seedSample(from: try sample(), defaults: defaults)
        first.remove(try XCTUnwrap(first.charts.first))

        let nextLaunch = ChartLibrary(directory: scratch)
        nextLaunch.seedSample(from: try sample(), defaults: defaults)
        XCTAssertTrue(nextLaunch.charts.isEmpty)
    }

    /// A seed that failed must not be recorded as done, or one bad first
    /// launch would cost that install its sample for good.
    func testASeedThatFailsIsTriedAgain() throws {
        let library = ChartLibrary(directory: scratch)
        // Outside the library's own folder on purpose. A path INSIDE it is a
        // chart the library already holds as far as `add` is concerned, and
        // adding one of those is a success with nothing to copy.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-there-\(UUID().uuidString).pdf")
        library.seedSample(from: missing, defaults: defaults)
        library.seedSample(from: nil, defaults: defaults)
        XCTAssertTrue(library.charts.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: SampleChart.seededKey))

        library.seedSample(from: try sample(), defaults: defaults)
        XCTAssertEqual(library.charts.count, 1)
    }

    /// The sample does not push out or disturb a chart that is already there.
    func testSeedingLeavesAStudentsOwnChartsAlone() throws {
        let library = ChartLibrary(directory: scratch)
        let own = FileManager.default.temporaryDirectory
            .appendingPathComponent("Show Opener - \(UUID().uuidString).pdf")
        try Data("mine".utf8).write(to: own)
        defer { try? FileManager.default.removeItem(at: own) }
        try library.add(from: own)

        library.seedSample(from: try sample(), defaults: defaults)
        XCTAssertEqual(library.charts.count, 2)
    }
}
