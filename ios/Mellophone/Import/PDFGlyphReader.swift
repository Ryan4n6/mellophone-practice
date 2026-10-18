import CoreGraphics
import Foundation

/// Walks a PDF page's content stream and reports where everything is.
///
/// The whole score-import feature rests on this file, because Sam's charts are
/// engraved rather than scanned: the notation arrives as positioned font glyphs
/// with a ToUnicode CMap, so reading them is parsing, not recognition.
///
/// CGPDFScanner's callbacks are `@convention(c)` and therefore CANNOT CAPTURE.
/// State travels through the scanner's info pointer as an unretained reference
/// to a class instance, which is why `State` is a class and why `read` holds a
/// strong reference for the whole scan. Getting that wrong does not crash: the
/// callbacks simply write nowhere and the page comes back empty, which reads
/// downstream as "this PDF has no notation in it".
///
/// This file knows nothing about music, and it does not filter by font. A staff
/// line, a stem, a beam, a barline and a slur are all paths here; deciding which
/// is which is ScoreBuilder's job.
enum PDFGlyphReader {

    /// What one font resource on the page can tell us.
    fileprivate struct FontInfo {
        let baseFont: String
        /// Glyph code to Unicode, from the font's ToUnicode CMap. Empty when the
        /// font has none, in which case the code is used as the scalar, which is
        /// right for the single-byte fonts that omit it.
        let toUnicode: [UInt32: UInt32]
        /// Type0 fonts encode two bytes per glyph. Everything else is one.
        let twoByte: Bool
        /// Glyph code to advance width in 1/1000 em.
        let widths: [UInt32: Double]
        let defaultWidth: Double
    }

    fileprivate final class State {
        var ctm: CGAffineTransform = .identity
        var ctmStack: [CGAffineTransform] = []
        var textMatrix: CGAffineTransform = .identity
        var lineMatrix: CGAffineTransform = .identity
        var leading: Double = 0
        var fontSize: Double = 0
        var fontKey: String = ""
        var fonts: [String: FontInfo] = [:]
        /// Subpaths of the path currently being built, NOT one flat point list.
        /// Engravers draw all five staff lines as subpaths of a single path and
        /// paint them with one operator; flattening them gives one box spanning
        /// the whole staff, and every staff line then fails a thickness test.
        var pending: [[CGPoint]] = []
        /// Indices into `pending` of the subpaths that took a curve segment.
        /// A curve keeps only its endpoint (see the "c" operator), so without
        /// this a slur reads as a straight line the size of a beam (#39).
        var curved: Set<Int> = []
        var glyphs: [PlacedGlyph] = []
        var paths: [PlacedPath] = []

        var currentFont: FontInfo? { fonts[fontKey] }
    }

    // MARK: - Entry point

    static func read(page: CGPDFPage) -> PageGeometry {
        let state = State()
        state.fonts = readFontResources(page: page)

        guard let table = CGPDFOperatorTableCreate() else {
            Log.score.error("[IMPORT] could not create an operator table")
            return .empty
        }
        defer { CGPDFOperatorTableRelease(table) }
        install(into: table)

        // passUnretained is correct ONLY because `state` is a local that lives
        // past CGPDFScannerScan below. Do not turn this into a temporary.
        let info = Unmanaged.passUnretained(state).toOpaque()
        let stream = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(stream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)

        Log.score.info("[IMPORT] page read: \(state.glyphs.count, privacy: .public) glyphs, \(state.paths.count, privacy: .public) paths")
        return PageGeometry(glyphs: state.glyphs, paths: state.paths)
    }

    // MARK: - Callback plumbing

    fileprivate static func state(_ info: UnsafeMutableRawPointer?) -> State? {
        guard let info else { return nil }
        return Unmanaged<State>.fromOpaque(info).takeUnretainedValue()
    }

    /// Pop `count` numbers. Operands come off the stack in REVERSE source order,
    /// so this fills the array backwards. Popping forwards yields a transposed
    /// matrix that looks almost right and puts every note in the wrong place.
    fileprivate static func popNumbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [Double]? {
        var values = [Double](repeating: 0, count: count)
        for i in stride(from: count - 1, through: 0, by: -1) {
            var v: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &v) else { return nil }
            values[i] = Double(v)
        }
        return values
    }

    private static func install(into table: CGPDFOperatorTableRef) {

        // MARK: graphics state

        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            s.ctmStack.append(s.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            if let top = s.ctmStack.popLast() { s.ctm = top }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 6) else { return }
            let m = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            s.ctm = m.concatenating(s.ctm)
        }

        // MARK: text state

        CGPDFOperatorTableSetCallback(table, "BT") { _, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            s.textMatrix = .identity
            s.lineMatrix = .identity
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            var size: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &size) else { return }
            var name: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            s.fontSize = Double(size)
            s.fontKey = String(cString: name)
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 1) else { return }
            s.leading = v[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 6) else { return }
            s.lineMatrix = CGAffineTransform(a: v[0], b: v[1], c: v[2],
                                             d: v[3], tx: v[4], ty: v[5])
            s.textMatrix = s.lineMatrix
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 2) else { return }
            PDFGlyphReader.nextLine(s, tx: v[0], ty: v[1])
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 2) else { return }
            s.leading = -v[1]
            PDFGlyphReader.nextLine(s, tx: v[0], ty: v[1])
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            PDFGlyphReader.nextLine(s, tx: 0, ty: -s.leading)
        }

        // MARK: text showing

        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            PDFGlyphReader.show(s, string)
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            PDFGlyphReader.nextLine(s, tx: 0, ty: -s.leading)
            PDFGlyphReader.show(s, string)
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            for i in 0..<CGPDFArrayGetCount(array) {
                var string: CGPDFStringRef?
                if CGPDFArrayGetString(array, i, &string), let string {
                    PDFGlyphReader.show(s, string)
                    continue
                }
                var adjust: CGPDFReal = 0
                if CGPDFArrayGetNumber(array, i, &adjust) {
                    // A positive kern moves the next glyph LEFT, in 1/1000 em.
                    let dx = -Double(adjust) / 1000 * s.fontSize
                    s.textMatrix = CGAffineTransform(translationX: dx, y: 0)
                        .concatenating(s.textMatrix)
                }
            }
        }

        // MARK: path construction

        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 2) else { return }
            // "m" BEGINS a subpath. That is the whole reason pending is nested.
            s.pending.append([CGPoint(x: v[0], y: v[1]).applying(s.ctm)])
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 2) else { return }
            PDFGlyphReader.extend(s, CGPoint(x: v[0], y: v[1]).applying(s.ctm))
        }
        // Curves contribute only their endpoint. Control points lie outside the
        // drawn shape and would inflate a slur's bounds into the staff above it.
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 6) else { return }
            PDFGlyphReader.extend(s, CGPoint(x: v[4], y: v[5]).applying(s.ctm))
            s.curved.insert(s.pending.count - 1)
        }
        CGPDFOperatorTableSetCallback(table, "v") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 4) else { return }
            PDFGlyphReader.extend(s, CGPoint(x: v[2], y: v[3]).applying(s.ctm))
            s.curved.insert(s.pending.count - 1)
        }
        CGPDFOperatorTableSetCallback(table, "y") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 4) else { return }
            PDFGlyphReader.extend(s, CGPoint(x: v[2], y: v[3]).applying(s.ctm))
            s.curved.insert(s.pending.count - 1)
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let s = PDFGlyphReader.state(info),
                  let v = PDFGlyphReader.popNumbers(scanner, 4) else { return }
            let (x, y, w, h) = (v[0], v[1], v[2], v[3])
            // "re" is a COMPLETE closed subpath of its own, not four more points
            // on whatever came before it.
            s.pending.append([CGPoint(x: x, y: y), CGPoint(x: x + w, y: y),
                              CGPoint(x: x + w, y: y + h), CGPoint(x: x, y: y + h)]
                                .map { $0.applying(s.ctm) })
        }

        // MARK: path painting

        for op in ["f", "F", "f*", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                guard let s = PDFGlyphReader.state(info) else { return }
                PDFGlyphReader.flush(s, filled: true)
            }
        }
        for op in ["S", "s"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                guard let s = PDFGlyphReader.state(info) else { return }
                PDFGlyphReader.flush(s, filled: false)
            }
        }
        // "n" paints nothing. It still ends the path, and dropping the points is
        // the point: every clip rectangle in the file arrives this way and would
        // otherwise look like a very large filled shape.
        CGPDFOperatorTableSetCallback(table, "n") { _, info in
            guard let s = PDFGlyphReader.state(info) else { return }
            s.pending.removeAll()
            s.curved.removeAll()
        }
    }

    // MARK: - Operator helpers

    fileprivate static func nextLine(_ s: State, tx: Double, ty: Double) {
        s.lineMatrix = CGAffineTransform(translationX: tx, y: ty).concatenating(s.lineMatrix)
        s.textMatrix = s.lineMatrix
    }

    /// Add a point to the subpath in progress, starting one if a segment
    /// operator arrives without a preceding "m".
    fileprivate static func extend(_ s: State, _ point: CGPoint) {
        if s.pending.isEmpty { s.pending.append([]) }
        s.pending[s.pending.count - 1].append(point)
    }

    /// Emit ONE PlacedPath per subpath.
    ///
    /// Not one per painting operator. A five line staff arrives as five
    /// subpaths painted by a single "f", and merging them yields a box twenty
    /// points tall that no thickness test will ever call a staff line. Caught by
    /// running the reader against a real Sibelius chart: 6 staff line candidates
    /// where the reference implementation found 51.
    fileprivate static func flush(_ s: State, filled: Bool) {
        defer { s.pending.removeAll(); s.curved.removeAll() }
        for (index, subpath) in s.pending.enumerated() where !subpath.isEmpty {
            let xs = subpath.map(\.x), ys = subpath.map(\.y)
            let bounds = CGRect(x: xs.min()!, y: ys.min()!,
                                width: xs.max()! - xs.min()!,
                                height: ys.max()! - ys.min()!)
            s.paths.append(PlacedPath(vertices: subpath, filled: filled, bounds: bounds,
                                      hasCurves: s.curved.contains(index)))
        }
    }

    /// Emit one PlacedGlyph per code in the string, advancing the text matrix.
    fileprivate static func show(_ s: State, _ string: CGPDFStringRef) {
        guard let bytes = CGPDFStringGetBytePtr(string) else { return }
        let length = CGPDFStringGetLength(string)
        guard length > 0 else { return }

        let font = s.currentFont
        let twoByte = font?.twoByte ?? false
        let step = twoByte ? 2 : 1
        guard length >= step else { return }

        var index = 0
        while index + step <= length {
            let code: UInt32 = twoByte
                ? (UInt32(bytes[index]) << 8) | UInt32(bytes[index + 1])
                : UInt32(bytes[index])

            // No ToUnicode CMap means the code IS the character, which is how
            // the single-byte fonts that omit one are meant to be read.
            let scalar = font?.toUnicode[code] ?? code

            let trm = s.textMatrix.concatenating(s.ctm)
            let origin = CGPoint.zero.applying(trm)
            // The determinant carries the combined scale of every enclosing cm
            // and the text matrix. Music PDFs routinely set a 70pt font inside a
            // 0.2 scale, and the drawn size is the product, not the 70.
            let scale = (abs(trm.a * trm.d - trm.b * trm.c)).squareRoot()

            s.glyphs.append(PlacedGlyph(scalar: scalar,
                                        x: Double(origin.x),
                                        y: Double(origin.y),
                                        size: s.fontSize * scale,
                                        font: font?.baseFont ?? s.fontKey))

            let width = font?.widths[code] ?? font?.defaultWidth ?? 500
            let advance = width / 1000 * s.fontSize
            s.textMatrix = CGAffineTransform(translationX: advance, y: 0)
                .concatenating(s.textMatrix)
            index += step
        }
    }

    // MARK: - Font resources

    private static func readFontResources(page: CGPDFPage) -> [String: FontInfo] {
        guard let pageDict = page.dictionary else { return [:] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources),
              let resources else { return [:] }
        var fontDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "Font", &fontDict),
              let fontDict else { return [:] }

        var result: [String: FontInfo] = [:]
        withUnsafeMutablePointer(to: &result) { pointer in
            CGPDFDictionaryApplyFunction(fontDict, { key, object, context in
                guard let context else { return }
                let out = context.assumingMemoryBound(to: [String: FontInfo].self)
                var dict: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { return }
                out.pointee[String(cString: key)] = PDFGlyphReader.fontInfo(from: dict)
            }, pointer)
        }
        return result
    }

    fileprivate static func fontInfo(from dict: CGPDFDictionaryRef) -> FontInfo {
        var baseFont = ""
        var namePointer: UnsafePointer<Int8>?
        if CGPDFDictionaryGetName(dict, "BaseFont", &namePointer), let namePointer {
            baseFont = String(cString: namePointer)
        }

        var subtype = ""
        var subtypePointer: UnsafePointer<Int8>?
        if CGPDFDictionaryGetName(dict, "Subtype", &subtypePointer), let subtypePointer {
            subtype = String(cString: subtypePointer)
        }
        let twoByte = subtype == "Type0"

        var toUnicode: [UInt32: UInt32] = [:]
        var stream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(dict, "ToUnicode", &stream), let stream {
            var format: CGPDFDataFormat = .raw
            if let data = CGPDFStreamCopyData(stream, &format) as Data? {
                toUnicode = parseToUnicode(String(decoding: data, as: UTF8.self))
            }
        }

        // Simple fonts carry /FirstChar and a flat /Widths array. Type0 fonts
        // carry /DW plus a /W range list; only /DW is read here, because every
        // engraver in issue #19 gives each glyph its own Td and the advance is
        // never what places a notehead.
        var widths: [UInt32: Double] = [:]
        var defaultWidth: Double = twoByte ? 1000 : 500
        var dw: CGPDFReal = 0
        if CGPDFDictionaryGetNumber(dict, "DW", &dw) { defaultWidth = Double(dw) }

        var firstChar: CGPDFInteger = 0
        var widthsArray: CGPDFArrayRef?
        if CGPDFDictionaryGetInteger(dict, "FirstChar", &firstChar),
           CGPDFDictionaryGetArray(dict, "Widths", &widthsArray), let widthsArray {
            for i in 0..<CGPDFArrayGetCount(widthsArray) {
                var w: CGPDFReal = 0
                if CGPDFArrayGetNumber(widthsArray, i, &w) {
                    widths[UInt32(firstChar) + UInt32(i)] = Double(w)
                }
            }
        }

        return FontInfo(baseFont: baseFont, toUnicode: toUnicode,
                        twoByte: twoByte, widths: widths, defaultWidth: defaultWidth)
    }

    /// Parse the `bfchar` and `bfrange` sections of a ToUnicode CMap.
    ///
    /// Three forms appear in the wild and all three are needed: both charts in
    /// issue #19 use the bracketed bfrange (`<01> <11> [<E044> <E262> ...]`),
    /// Finale emits bfchar pairs, and the incrementing bfrange
    /// (`<lo> <hi> <ustart>`) turns up in text fonts.
    static func parseToUnicode(_ cmap: String) -> [UInt32: UInt32] {
        var map: [UInt32: UInt32] = [:]

        func hexValues(_ section: String) -> [String] {
            section.split(whereSeparator: { $0 == "<" || $0 == ">" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.allSatisfy(\.isHexDigit) }
        }

        for section in cmap.components(separatedBy: "beginbfchar").dropFirst() {
            let body = section.components(separatedBy: "endbfchar")[0]
            let values = hexValues(body)
            for pair in stride(from: 0, to: values.count - 1, by: 2) {
                guard let src = UInt32(values[pair], radix: 16),
                      let dst = UInt32(values[pair + 1].prefix(4), radix: 16) else { continue }
                map[src] = dst
            }
        }

        for section in cmap.components(separatedBy: "beginbfrange").dropFirst() {
            let body = section.components(separatedBy: "endbfrange")[0]
            // Tokenised rather than split by line: a bracketed range is free to
            // wrap, and a line-based parse drops whatever falls past the break
            // without ever reporting that it did.
            var tokens: [String] = []
            var current = ""
            var inAngle = false
            for character in body {
                switch character {
                case "<": inAngle = true; current = ""
                case ">": inAngle = false; tokens.append(current); current = ""
                case "[", "]": if !inAngle { tokens.append(String(character)) }
                default: if inAngle { current.append(character) }
                }
            }

            var i = 0
            while i + 2 < tokens.count {
                guard let lo = UInt32(tokens[i], radix: 16),
                      let hi = UInt32(tokens[i + 1], radix: 16), lo <= hi else { i += 1; continue }
                if tokens[i + 2] == "[" {
                    var offset: UInt32 = 0
                    var j = i + 3
                    while j < tokens.count, tokens[j] != "]" {
                        if let dst = UInt32(tokens[j].prefix(4), radix: 16) {
                            map[lo + offset] = dst
                        }
                        offset += 1
                        j += 1
                    }
                    i = j + 1
                } else {
                    if let start = UInt32(tokens[i + 2].prefix(4), radix: 16), hi - lo < 65_536 {
                        for code in lo...hi { map[code] = start + (code - lo) }
                    }
                    i += 3
                }
            }
        }
        return map
    }
}
