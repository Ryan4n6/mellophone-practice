import OSLog
import UIKit

/// The paper a student prints lyre cards on (#43).
enum LyreCardSheet: String, CaseIterable, Identifiable {
    /// US Letter, two cards to a sheet with cut lines, for a home printer.
    case letter
    /// A4, the same.
    case a4
    /// One card per page at card size, for card stock or a print shop.
    case cards

    var id: String { rawValue }

    var label: String {
        switch self {
        case .letter: "Letter, 2 per sheet"
        case .a4: "A4, 2 per sheet"
        case .cards: "Card size pages"
        }
    }

    var pageSize: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .cards: LyreCardPrint.cardSize
        }
    }

    var cardsPerPage: Int { self == .cards ? 1 : 2 }
}

/// Builds the printable PDF of a chart's lyre cards (#43).
///
/// The music is the director's page drawn with `drawPDFPage`, clipped to each
/// line, so it stays vector and prints as sharp as the original. Built on the
/// phone from the student's own copy and handed to the share sheet; nothing
/// goes anywhere the student does not send it.
enum LyreCardPDF {

    enum Failure: Error { case unreadableChart }

    static func make(chart: URL, score: Score, sheet: LyreCardSheet, title: String) throws -> URL {
        guard let document = CGPDFDocument(chart as CFURL) else {
            Log.score.error("[CARD] could not open \(chart.lastPathComponent, privacy: .public) to print it")
            throw Failure.unreadableChart
        }
        let systems = score.systems
        let layout = LyreCardPrint.layout(systems)
        let left = systems.map { LyreCards.strip($0).minX }.min() ?? 0
        let size = sheet.pageSize
        let card = LyreCardPrint.cardSize
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(title) lyre cards.pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        try renderer.writePDF(to: file) { context in
            let pages = stride(from: 0, to: layout.cards.count, by: sheet.cardsPerPage)
            for first in pages {
                context.beginPage()
                let onPage = layout.cards[first..<min(first + sheet.cardsPerPage, layout.cards.count)]
                // Two cards stacked and centred, touching, so one cut between
                // them serves both.
                let top = (size.height - card.height * CGFloat(sheet.cardsPerPage)) / 2
                for (slot, lines) in onPage.enumerated() {
                    let origin = CGPoint(x: (size.width - card.width) / 2, y: top + CGFloat(slot) * card.height)
                    draw(lines, of: systems, from: document, at: origin, scale: layout.scale, left: left,
                         label: label(title: title, systems: systems, card: lines),
                         cutLine: sheet != .cards, in: context.cgContext)
                }
            }
        }
        let pageCount = (layout.cards.count + sheet.cardsPerPage - 1) / sheet.cardsPerPage
        Log.score.info("[CARD] printed \(layout.cards.count, privacy: .public) cards on \(pageCount, privacy: .public) pages (\(sheet.rawValue, privacy: .public)) for \(title, privacy: .public)")
        #if DEBUG
        FileLog.write("[CARD] printed \(layout.cards.count) cards on \(pageCount) pages (\(sheet.rawValue))")
        #endif
        return file
    }

    /// "PEAK mello  ·  bars 1 to 35".
    static func label(title: String, systems: [SystemPlace], card: Range<Int>) -> String {
        let measures = systems[card].flatMap(\.bars).map(\.measure)
        return "\(title)  ·  bars \(measures.min() ?? 0) to \(measures.max() ?? 0)"
    }

    private static func draw(_ lines: Range<Int>, of systems: [SystemPlace], from document: CGPDFDocument,
                             at origin: CGPoint, scale: CGFloat, left: CGFloat, label: String,
                             cutLine: Bool, in cg: CGContext) {
        let card = LyreCardPrint.cardSize
        if cutLine {
            cg.setStrokeColor(UIColor(white: 0.75, alpha: 1).cgColor)
            cg.setLineWidth(0.5)
            cg.stroke(CGRect(origin: origin, size: card))
        }
        // Nothing above the ring strip: the sleeve hides it.
        var y = origin.y + LyreCardPrint.ringStrip
        for index in lines {
            let strip = LyreCards.strip(systems[index])
            guard let page = document.page(at: systems[index].page + 1) else {
                Log.score.error("[CARD] page \(systems[index].page + 1, privacy: .public) is missing, line \(index + 1, privacy: .public) not printed")
                continue
            }
            let height = strip.height * scale
            let x = origin.x + LyreCardPrint.edge + (strip.minX - left) * scale
            cg.saveGState()
            // UIKit's y runs down and the PDF's up.
            cg.translateBy(x: x, y: y + height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -strip.minX, y: -strip.minY)
            cg.clip(to: strip)
            cg.drawPDFPage(page)
            cg.restoreGState()
            y += height
        }
        // Bottom right, inside the edge margin's line, where a line of music
        // rarely reaches and where a thumb flipping the stack reads it.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7),
            .foregroundColor: UIColor(white: 0.45, alpha: 1),
        ]
        let text = label as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: origin.x + card.width - LyreCardPrint.edge - textSize.width,
                              y: origin.y + card.height - LyreCardPrint.edge - textSize.height),
                  withAttributes: attributes)
    }
}
