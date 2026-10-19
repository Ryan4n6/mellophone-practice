import XCTest
@testable import Mellophone

/// Printed lyre cards (#43): the PDF a student sends to a printer, measured.
final class LyreCardPrintTests: XCTestCase {

    private var url: URL!
    private var score: Score!

    override func setUpWithError() throws {
        url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "card-turns", withExtension: "pdf"))
        score = try ScoreImporter.readOrThrow(url: url)
    }

    /// The fixture's seven lines fit one card; three copies of them make a
    /// part long enough to need several.
    private var longScore: Score {
        Score(events: [], timeSignature: (4, 4), keySignature: -1, voiceCount: 1, suspectMeasures: [],
              unreadableSymbols: [], systems: score.systems + score.systems + score.systems)
    }

    private func pages(_ file: URL) throws -> [CGPDFPage] {
        let document = try XCTUnwrap(CGPDFDocument(file as CFURL))
        return (1...document.numberOfPages).compactMap { document.page(at: $0) }
    }

    func testCardPagesAreCardSized() throws {
        let file = try LyreCardPDF.make(chart: url, score: longScore, sheet: .cards, title: "Card Turns")
        let printed = try pages(file)
        XCTAssertEqual(printed.count, LyreCardPrint.layout(longScore.systems).cards.count)
        for page in printed {
            let box = page.getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, 504.57, accuracy: 0.1)
            XCTAssertEqual(box.height, 379.84, accuracy: 0.1)
        }
    }

    func testLetterHoldsTwoCardsPerSheet() throws {
        let cards = LyreCardPrint.layout(longScore.systems).cards.count
        let printed = try pages(try LyreCardPDF.make(chart: url, score: longScore, sheet: .letter, title: "Card Turns"))
        XCTAssertEqual(printed.count, (cards + 1) / 2)
        XCTAssertEqual(printed[0].getBoxRect(.mediaBox).size, CGSize(width: 612, height: 792))
    }

    func testA4HoldsTwoCardsPerSheet() throws {
        let cards = LyreCardPrint.layout(longScore.systems).cards.count
        let printed = try pages(try LyreCardPDF.make(chart: url, score: longScore, sheet: .a4, title: "Card Turns"))
        XCTAssertEqual(printed.count, (cards + 1) / 2)
        let box = printed[0].getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 595.28, accuracy: 0.1)
        XCTAssertEqual(box.height, 841.89, accuracy: 0.1)
    }

    /// The top 2.2 cm of a card goes under the sleeve's ring strip, and
    /// anything printed there is hidden: every pixel of it must be white.
    /// The music below it must not be.
    func testNothingIsDrawnInTheRingStrip() throws {
        for page in try pages(try LyreCardPDF.make(chart: url, score: longScore, sheet: .cards, title: "Card Turns")) {
            let box = page.getBoxRect(.mediaBox)
            let k: CGFloat = 2, width = Int(box.width * k), height = Int(box.height * k)
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: k, y: k)
            context.drawPDFPage(page)
            let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
            // Row 0 of the buffer is the TOP of the page.
            func darkest(rows: Range<Int>) -> UInt8 {
                var low: UInt8 = 255
                for row in rows { for column in 0..<width { low = min(low, pixels[(row * width + column) * 4]) } }
                return low
            }
            let strip = Int(LyreCardPrint.ringStrip * k)
            XCTAssertGreaterThanOrEqual(darkest(rows: 0..<strip - 1), 250, "ink under the ring strip")
            XCTAssertLessThan(darkest(rows: strip..<height), 100, "no music on the card")
        }
    }

    /// PEAK's cards, written next to Sam's charts in the gitignored local
    /// folder so they can be rendered and looked at. Never committed.
    func testPEAKPrintsEveryLineOnCards() throws {
        let local = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/local")
        let peak = local.appendingPathComponent("PEAK mello.pdf")
        guard FileManager.default.fileExists(atPath: peak.path) else { throw XCTSkip("PEAK is not on this machine") }
        let score = try ScoreImporter.readOrThrow(url: peak)
        let layout = LyreCardPrint.layout(score.systems)
        XCTAssertEqual(layout.cards.flatMap { Array($0) }, Array(score.systems.indices))
        let out = local.appendingPathComponent("printed")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for sheet in LyreCardSheet.allCases {
            let file = try LyreCardPDF.make(chart: peak, score: score, sheet: sheet, title: "PEAK mello")
            let kept = out.appendingPathComponent("PEAK \(sheet.rawValue).pdf")
            try? FileManager.default.removeItem(at: kept)
            try FileManager.default.copyItem(at: file, to: kept)
        }
    }

    /// Each card says which chart and bars it holds, so a dropped stack can be
    /// put back in order.
    func testEachCardIsLabelledWithItsBars() {
        let systems = longScore.systems
        let layout = LyreCardPrint.layout(systems)
        let first = LyreCardPDF.label(title: "Card Turns", systems: systems, card: layout.cards[0])
        XCTAssertTrue(first.hasPrefix("Card Turns"))
        XCTAssertTrue(first.contains("bars 1 to"), first)
    }
}
