import OSLog
import UIKit

/// Lines of the director's PDF, cut out and drawn at screen size (#43).
///
/// Drawn from the user's own copy of the chart with `CGPDFPage`, so the music
/// is the engraver's and nothing is redrawn. Each strip is drawn once per size
/// and kept for the life of the screen: a card turn is then a swap of images
/// already made, not four PDF renders while the music plays.
final class CardStrips {
    private let document: CGPDFDocument?
    private var cache: [String: UIImage] = [:]

    init(url: URL) {
        document = CGPDFDocument(url as CFURL)
        if document == nil {
            Log.score.error("[CARD] could not open \(url.lastPathComponent, privacy: .public) to draw its lines")
        }
    }

    func image(_ system: SystemPlace, index: Int, size: CGSize, scale: CGFloat, displayScale: CGFloat) -> UIImage? {
        let key = "\(index):\(Int(size.width.rounded()))"
        if let cached = cache[key] { return cached }
        guard let page = document?.page(at: system.page + 1) else {
            Log.score.error("[CARD] page \(system.page + 1, privacy: .public) of the chart is missing, line \(index + 1, privacy: .public) not drawn")
            return nil
        }
        let strip = LyreCards.strip(system)
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            // UIKit's y runs down and the PDF's up.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -strip.minX, y: -strip.minY)
            cg.clip(to: strip)
            cg.drawPDFPage(page)
        }
        cache[key] = image
        return image
    }
}

/// Holds one chart's strips for the life of the card view (#51). Publishes
/// nothing on purpose: the strips are a cache, and a cache filling must not
/// redraw the screen that asked for it.
final class CardStripsHolder: ObservableObject {
    private var made: (url: URL, strips: CardStrips)?

    func strips(for url: URL) -> CardStrips {
        if let made, made.url == url { return made.strips }
        let strips = CardStrips(url: url)
        made = (url, strips)
        Log.score.info("[CARD] strips opened for \(url.lastPathComponent, privacy: .public)")
        return strips
    }
}
