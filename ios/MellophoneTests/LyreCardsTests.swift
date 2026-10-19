import XCTest
@testable import Mellophone

/// How a chart is dealt out into cards (#43), on the screen and on paper.
final class LyreCardsTests: XCTestCase {

    private func fixture(_ name: String) throws -> Score {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "pdf"))
        return try ScoreImporter.readOrThrow(url: url)
    }

    func testFourLinesToACardAcrossAPageBreak() throws {
        let cards = LyreCards.cards(try fixture("card-turns").systems, linesPerCard: 4)
        XCTAssertEqual(cards.map(\.systems), [0..<4, 4..<7])
        XCTAssertEqual(cards.map(\.firstMeasure), [1, 13])
        XCTAssertEqual(cards.map(\.lastMeasure), [12, 21])
        XCTAssertEqual(cards.map(\.index), [0, 1])
    }

    func testTwoLinesToACard() throws {
        let cards = LyreCards.cards(try fixture("card-turns").systems, linesPerCard: 2)
        XCTAssertEqual(cards.map(\.systems), [0..<2, 2..<4, 4..<6, 6..<7])
    }

    /// Asking for more than four or fewer than two is clamped, the same as
    /// the preference is.
    func testLinesPerCardIsClampedToTwoToFour() throws {
        let systems = try fixture("card-turns").systems
        XCTAssertEqual(LyreCards.cards(systems, linesPerCard: 9), LyreCards.cards(systems, linesPerCard: 4))
        XCTAssertEqual(LyreCards.cards(systems, linesPerCard: 1), LyreCards.cards(systems, linesPerCard: 2))
    }

    func testFewerLinesThanACardIsOneCard() throws {
        let cards = LyreCards.cards(try fixture("reader-traps").systems, linesPerCard: 4)
        XCTAssertEqual(cards.map(\.systems), [0..<2])
    }

    func testCardHoldingAMeasure() throws {
        let cards = LyreCards.cards(try fixture("card-turns").systems, linesPerCard: 4)
        XCTAssertEqual(LyreCards.index(holding: 12, in: cards), 0)
        XCTAssertEqual(LyreCards.index(holding: 13, in: cards), 1)
        XCTAssertNil(LyreCards.index(holding: 99, in: cards))
    }

    /// A strip holds the line's ink with a half space to spare, and starts two
    /// half spaces left of the staff so the clef is not cut.
    func testAStripHoldsTheLinesInk() throws {
        let system = try fixture("reader-traps").systems[0]
        let strip = LyreCards.strip(system)
        XCTAssertEqual(strip.minX, system.xRange.lowerBound - 2 * system.halfSpace, accuracy: 0.001)
        XCTAssertEqual(strip.maxX, system.xRange.upperBound + system.halfSpace, accuracy: 0.001)
        XCTAssertEqual(strip.minY, system.inkBottom - system.halfSpace, accuracy: 0.001)
        XCTAssertEqual(strip.maxY, system.inkTop + system.halfSpace, accuracy: 0.001)
    }

    func testPrintedCardsKeepEveryLineOnceAndFitTheCard() throws {
        let systems = try fixture("card-turns").systems
        let layout = LyreCardPrint.layout(systems)
        XCTAssertEqual(layout.cards.flatMap { Array($0) }, Array(0..<7))
        let room = LyreCardPrint.cardSize.height - LyreCardPrint.ringStrip - LyreCardPrint.edge
        for card in layout.cards {
            let height = card.map { LyreCards.strip(systems[$0]).height * layout.scale }.reduce(0, +)
            XCTAssertLessThanOrEqual(height, room, "card \(card) runs past the bottom")
        }
        let widest = systems.map { LyreCards.strip($0).width }.max()!
        XCTAssertEqual(widest * layout.scale, LyreCardPrint.musicWidth, accuracy: 0.5)
    }

    /// Our fixture's seven lines all fit one printed card, so a part three
    /// times as long is what makes a card fill and the next one start.
    func testALongPartFillsCardsInOrderWithoutSplittingALine() throws {
        let one = try fixture("card-turns").systems
        let systems = one + one + one
        let layout = LyreCardPrint.layout(systems)
        XCTAssertGreaterThan(layout.cards.count, 1)
        XCTAssertEqual(layout.cards.flatMap { Array($0) }, Array(0..<21))
        let room = LyreCardPrint.cardSize.height - LyreCardPrint.ringStrip - LyreCardPrint.edge
        for (card, next) in zip(layout.cards, layout.cards.dropFirst()) {
            let used = card.map { LyreCards.strip(systems[$0]).height * layout.scale }.reduce(0, +)
            let following = LyreCards.strip(systems[next.lowerBound]).height * layout.scale
            XCTAssertGreaterThan(used + following, room, "card \(card) had room for the next line")
        }
    }

    /// The card is 17.8 by 13.4 cm, two millimetres under the sleeve each way.
    func testCardSizeIsTheSleeveLessTwoMillimetres() {
        let cm = 72 / 2.54
        XCTAssertEqual(LyreCardPrint.cardSize.width, 17.8 * cm, accuracy: 0.01)
        XCTAssertEqual(LyreCardPrint.cardSize.height, 13.4 * cm, accuracy: 0.01)
        XCTAssertEqual(LyreCardPrint.ringStrip, 2.2 * cm, accuracy: 0.01)
        XCTAssertEqual(LyreCardPrint.edge, 0.4 * cm, accuracy: 0.01)
        XCTAssertEqual(LyreCardPrint.musicWidth, 17.0 * cm, accuracy: 0.01)
    }

    func testPEAKCardsStartAtThePrintedBars() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/local/PEAK mello.pdf")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("PEAK is not on this machine") }
        let cards = LyreCards.cards(try ScoreImporter.readOrThrow(url: url).systems, linesPerCard: 4)
        XCTAssertEqual(cards.prefix(3).map(\.firstMeasure), [1, 36, 65])
        XCTAssertEqual(LyreCards.index(holding: 34, in: cards), 0)
    }
}
