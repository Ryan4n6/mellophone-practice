import CoreGraphics
import Foundation

enum RasterPageReader {

    /// Every page of a document that is a picture, read (#49). Nil when no
    /// page carries an image to read.
    @_optimize(speed) static func read(_ document: CGPDFDocument) -> [PageGeometry]? {
        guard document.numberOfPages > 0 else { return nil }
        var pages: [PageGeometry] = []
        var seen: [UInt64: Int] = [:]
        var any = false
        for index in 1...document.numberOfPages {
            guard let page = document.page(at: index), largestImageWidth(on: page) != nil,
                  let bitmap = InkBitmap.render(page: page) else { continue }
            any = true
            // A page printed again is read once. The ePrint in #49 was a four
            // copy purchase printed to one PDF, its two pages four times
            // over, and read as it stood the part played four times.
            // It stays in the list as an empty page, so every later page keeps
            // its own index: the card view cuts lines from the page a line
            // was read from.
            let print = fingerprint(bitmap)
            if let first = seen[print] {
                Log.score.info("[RASTER] page \(index, privacy: .public) is page \(first, privacy: .public) again, skipped")
                pages.append(.empty)
                continue
            }
            seen[print] = index
            let started = Date()
            let geometry = RasterRecognizer.read(bitmap)
            Log.score.info("[RASTER] page \(index, privacy: .public) read in \(Date().timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public) s: \(geometry.glyphs.count, privacy: .public) glyphs, \(geometry.paths.count, privacy: .public) paths")
            pages.append(geometry)
        }
        return any ? pages : nil
    }

    /// FNV-1a over the ink. Two prints of one page are the same image drawn
    /// the same way, so their ink is identical to the pixel.
    @_optimize(speed) static func fingerprint(_ bitmap: InkBitmap) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        bitmap.ink.withUnsafeBufferPointer { ink in
            for byte in ink { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        }
        hash = (hash ^ UInt64(bitmap.width)) &* 0x100000001b3
        return (hash ^ UInt64(bitmap.height)) &* 0x100000001b3
    }

    /// The pixel width of the widest image drawn on a page, read from the
    /// page's own XObject dictionary, so the page can be drawn back at the
    /// resolution it was printed at.
    @_optimize(speed) static func largestImageWidth(on page: CGPDFPage) -> Int? {
        guard let pageDict = page.dictionary else { return nil }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources), let resources else { return nil }
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return nil }
        var widest: Int?
        CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dict = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Image" else { return true }
            var width: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(dict, "Width", &width) { widest = max(widest ?? 0, Int(width)) }
            return true
        }, nil)
        return widest
    }
}
