import XCTest
@testable import Mellophone

/// Where the reader says every note, line and bar was printed (#43).
///
/// The card view boxes the playing note on the director's own page and cuts
/// each line out of it, so a placement that is off by a line puts the box on
/// the wrong note, which is worse than no box. These read our own engraved
/// fixtures, and Sam's charts where they exist.
final class PlacementTests: XCTestCase {

    private func fixture(_ name: String) throws -> Score {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "pdf"),
                                "\(name).pdf is not in the test bundle")
        return try ScoreImporter.readOrThrow(url: url)
    }

    private func local(_ name: String) throws -> Score {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/local/\(name)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) is not on this machine; the fixture tests still ran")
        }
        return try ScoreImporter.readOrThrow(url: url)
    }

    func testEveryPitchedEventOfTheTrapsFixtureIsPlacedOnItsSystem() throws {
        let score = try fixture("reader-traps")
        XCTAssertEqual(score.systems.count, 2)
        for event in score.events where !event.isRest {
            let place = try XCTUnwrap(event.place, "\(event.writtenName) in bar \(event.measure) has no place")
            let system = score.systems[place.system]
            XCTAssertLessThanOrEqual(abs(place.y - system.bottomLineY), 12 * system.halfSpace,
                                     "\(event.writtenName) in bar \(event.measure) is off its staff")
            XCTAssertTrue(system.xRange.contains(place.x), "\(event.writtenName) in bar \(event.measure) is off the line")
        }
    }

    func testBarsCoverEveryMeasureOnceInOrder() throws {
        let score = try fixture("reader-traps")
        let bars = score.systems.flatMap(\.bars)
        XCTAssertEqual(bars.map(\.measure), Array(1...9))
        for bar in bars { XCTAssertLessThan(bar.x0, bar.x1, "bar \(bar.measure) has no width") }
    }

    /// The traps fixture prints "♩ = 96" about 12 half spaces over its first
    /// line, and the strip has to hold it. The sample chart prints its title
    /// over its first line, and the strip must not.
    func testInkBoundsHoldTheTempoMarkButNotTheTitle() throws {
        let traps = try fixture("reader-traps").systems[0]
        XCTAssertGreaterThanOrEqual(traps.inkTop, traps.topLineY + 8 * traps.halfSpace)
        XCTAssertLessThanOrEqual(traps.inkTop, traps.topLineY + 14 * traps.halfSpace)

        // Measured 4.3 half spaces on 2026-10-18; the title is far higher, and
        // a strip stretched to the reach limit would mean it had been let in.
        let sampleURL = try XCTUnwrap(SampleChart.url)
        let sample = try ScoreImporter.readOrThrow(url: sampleURL).systems[0]
        XCTAssertLessThanOrEqual(sample.inkTop, sample.topLineY + 6 * sample.halfSpace)
    }

    /// Our own two page chart (#43): seven lines, four on the first page and
    /// three on the second, a line every three bars. The only chart we own
    /// with more than one card and a card that crosses a page.
    func testCardTurnsFixtureHasSevenLinesOverTwoPages() throws {
        let score = try fixture("card-turns")
        XCTAssertEqual(score.systems.count, 7)
        XCTAssertEqual(score.systems.map(\.page), [0, 0, 0, 0, 1, 1, 1])
        XCTAssertEqual(score.systems.compactMap(\.firstMeasure), [1, 4, 7, 10, 13, 16, 19])
        for event in score.events where !event.isRest {
            XCTAssertNotNil(event.place, "\(event.writtenName) in bar \(event.measure) has no place")
        }
    }

    /// PEAK page 1's staff bottom lines, measured off the page on 2026-10-18.
    func testPEAKPlacesEveryPitchedNote() throws {
        let score = try local("PEAK mello.pdf")
        XCTAssertGreaterThanOrEqual(score.systems.count, 9)
        for event in score.events where !event.isRest {
            XCTAssertNotNil(event.place, "\(event.writtenName) in bar \(event.measure) has no place")
        }
        let bottoms = score.systems.filter { $0.page == 0 }.prefix(9).map(\.bottomLineY)
        for (got, want) in zip(bottoms, [595.67, 531.19, 466.70, 402.08, 337.59, 272.24, 207.76, 143.13, 78.65]) {
            XCTAssertEqual(got, want, accuracy: 0.05)
        }
        XCTAssertEqual(score.systems.prefix(9).compactMap(\.firstMeasure), [1, 11, 20, 27, 36, 42, 49, 54, 65])
    }
}
