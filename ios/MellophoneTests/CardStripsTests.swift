import UIKit
import XCTest
@testable import Mellophone

/// The card view draws the director's own lines (#43, #51). Every geometry test
/// passed while the screen showed a white card with no music on it, because
/// none of them looked at the pixels. This one does.
final class CardStripsTests: XCTestCase {

    /// The share of a strip's pixels that are ink. A staff line alone is a few
    /// percent; white paper is zero.
    private func inkShare(_ image: UIImage) throws -> Double {
        let cg = try XCTUnwrap(image.cgImage)
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)
        return Double(pixels.filter { $0 < 128 }.count) / Double(pixels.count)
    }

    func testEveryLineOfTheSampleChartHasInkOnIt() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Sample Chart - Band Room March", withExtension: "pdf")
                                ?? Bundle.main.url(forResource: "Sample Chart - Band Room March", withExtension: "pdf"))
        let score = try ScoreImporter.readOrThrow(url: url)
        let card = try XCTUnwrap(LyreCards.cards(score.systems, linesPerCard: 4).first)
        let geometry = CardGeometry(systems: score.systems, card: card, width: 800)
        let strips = CardStrips(url: url)
        for index in card.systems {
            let frame = geometry.stripFrame(index)
            let image = try XCTUnwrap(strips.image(score.systems[index], index: index, size: frame.size,
                                                   scale: geometry.scale, displayScale: 2))
            let share = try inkShare(image)
            XCTAssertGreaterThan(share, 0.03, "line \(index + 1) is blank: \(share) ink, strip \(LyreCards.strip(score.systems[index]))")
        }
    }
}
