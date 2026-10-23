import CoreGraphics
import CoreText
import XCTest
@testable import Mellophone

/// A chart that is a picture of the page (#49): an ePrint printed to PDF, or
/// a scan. Read from its pixels into the geometry the vector reader makes,
/// then by the same ScoreBuilder.
///
/// What is real here, said once:
/// - `repeats-picture.pdf` and `band-room-march-picture.pdf` are OUR charts
///   (the repeat fixture and the app's sample chart), each drawn at 450 ppi
///   into an image only PDF, the way an ePrint arrives. The vector read of
///   the same chart is the answer, so a test here compares two real reads
///   and no expected value is typed in by hand.
/// - The Florida, PEAK and Arabian Dances tests read Sam's charts, only on a
///   machine that has them: copyrighted, gitignored, never in a build.
///   Florida and PEAK are vector PDFs and are drawn into pictures here, in a
///   temporary file; Arabian Dances is the ePrint itself.
final class RasterReaderTests: XCTestCase {

    // MARK: - Our charts, as pictures

    func testTheRepeatFixtureReadsFromItsPictureAsItDoesFromItsVectors() throws {
        let vector = try ScoreImporter.readOrThrow(url: fixture("repeats", "pdf"))
        let picture = try ScoreImporter.readOrThrow(url: fixture("repeats-picture", "pdf"))
        XCTAssertEqual(notes(picture), notes(vector))
        XCTAssertEqual(picture.repeats, vector.repeats, "both repeat signs and all four endings")
        XCTAssertEqual(picture.playOrder, vector.playOrder)
        XCTAssertEqual(tempos(picture), tempos(vector))
        XCTAssertEqual(picture.suspectMeasures, [])
    }

    func testTheSampleChartReadsFromItsPictureAsItDoesFromItsVectors() throws {
        let vector = try ScoreImporter.readOrThrow(url: sampleChart())
        let picture = try ScoreImporter.readOrThrow(url: fixture("band-room-march-picture", "pdf"))
        XCTAssertEqual(notes(picture), notes(vector))
        XCTAssertEqual(picture.keySignature, vector.keySignature)
        XCTAssertEqual(picture.timeSignature.beats, vector.timeSignature.beats)
        XCTAssertEqual(picture.timeSignature.unit, vector.timeSignature.unit)
        XCTAssertEqual(picture.suspectMeasures, [])
    }

    /// Every line keeps a place on its page, so the card view can cut it out
    /// of the picture the way it cuts one out of a vector page (#43).
    func testEveryLineOfAPictureHasItsPlace() throws {
        let vector = try ScoreImporter.readOrThrow(url: fixture("repeats", "pdf"))
        let picture = try ScoreImporter.readOrThrow(url: fixture("repeats-picture", "pdf"))
        XCTAssertEqual(picture.systems.count, vector.systems.count)
        for (p, v) in zip(picture.systems, vector.systems) {
            XCTAssertEqual(p.page, v.page)
            XCTAssertEqual(p.bars.map(\.measure), v.bars.map(\.measure))
            // A staff line found in the pixels is within half a pixel at
            // 450 ppi, a ninth of a point, of where the vector page drew it.
            for (a, b) in zip(p.lineYs, v.lineYs) { XCTAssertEqual(a, b, accuracy: 0.2) }
        }
        XCTAssertTrue(picture.events.filter { !$0.isRest }.allSatisfy { $0.place != nil },
                      "every note gets a box on the card")
    }

    /// An ePrint bought as four copies prints every page four times into one
    /// PDF. The part is read once.
    func testAPagePrintedAgainIsReadOnce() throws {
        let twice = try temporaryPDF(drawing: fixture("band-room-march-picture", "pdf"), pages: [1, 1, 1])
        defer { try? FileManager.default.removeItem(at: twice) }
        let once = try ScoreImporter.readOrThrow(url: fixture("band-room-march-picture", "pdf"))
        let read = try ScoreImporter.readOrThrow(url: twice)
        XCTAssertEqual(notes(read), notes(once))
        XCTAssertEqual(read.events.map(\.measure).max(), 16)
        XCTAssertEqual(Set(read.systems.map(\.page)), [0], "the copies keep their page numbers and hold no lines")
    }

    /// A picture with no staff in it is not a chart, and says so in the
    /// sentence for that.
    func testAPictureOfNoStaffIsRefused() throws {
        let blank = FileManager.default.temporaryDirectory.appendingPathComponent("blank-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: blank) }
        try writeImagePDF(to: blank, pages: 1) { context, size in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: size.width * 0.2, y: size.height * 0.5, width: size.width * 0.3, height: size.height * 0.05))
        }
        XCTAssertThrowsError(try ScoreImporter.readOrThrow(url: blank)) { error in
            XCTAssertEqual(error as? ImportError, .noStaffFound)
        }
    }

    // MARK: - Digits

    /// A digit drawn in two of the serif faces the phone carries, at the size
    /// a multi-bar rest's count is printed at 450 ppi, reads back as itself:
    /// the drawing, the box and the grid agree with the templates' own. The
    /// engraved digits are checked where they are printed, by the charts.
    func testEveryDigitReadsAsItself() throws {
        for face in ["TimesNewRomanPS-BoldMT", "Georgia-Bold"] {
            for digit in 0...9 {
                let bitmap = try drawn("\(digit)", face: face, height: 60)
                let box = try XCTUnwrap(inkBox(bitmap))
                let read = try XCTUnwrap(DigitReader.read(bitmap, box: box))
                XCTAssertEqual(read.digit, digit, "\(digit) in \(face)")
            }
        }
    }

    // MARK: - Sam's charts, where they exist

    /// Drawn into a picture here, then read: every bar matches the vector
    /// read but one, the lower note of a chord in bar 36, measured 2026-10-23.
    func testFloridaAsAPictureReadsAsItsVectorsDo() throws {
        let vector = try local("Florida Fight Song (Orange and Blue)-Horn in F.pdf")
        let picture = try ScoreImporter.readOrThrow(url: try drawnAsPicture(vector.url))
        let differing = differingBars(notes(picture), notes(vector.score))
        XCTAssertEqual(differing, [36], "bar 36 loses its Bb4 half note")
        XCTAssertEqual(picture.repeats, vector.score.repeats)
        XCTAssertEqual(tempos(picture), tempos(vector.score))
    }

    /// The same for PEAK, 251 bars of Sibelius: at most 11 differ, and the
    /// bar sum check flags every one whose rhythm is wrong, so a student is
    /// told; one that is not flagged has its rhythm right and a pitch off.
    /// Which bars those are moves with the drawing: a picture drawn here in
    /// the simulator loses bar 34 and keeps bar 49, the same page drawn on
    /// the Mac the other way round (measured 2026-10-23), because a few
    /// pixels of a ring's edge land on either side of the ink threshold.
    /// Ten of its twelve tempo marks are read, every one right; the other two
    /// are left to the student's number rather than guessed.
    func testPEAKAsAPictureReadsAsItsVectorsDo() throws {
        let vector = try local("PEAK mello.pdf")
        let picture = try ScoreImporter.readOrThrow(url: try drawnAsPicture(vector.url))
        let read = notes(picture), printed = notes(vector.score)
        let differing = differingBars(read, printed)
        XCTAssertLessThanOrEqual(differing.count, 11, "bars \(differing.sorted())")
        for bar in differing.subtracting(picture.suspectMeasures) {
            XCTAssertEqual(rhythm(read[bar]), rhythm(printed[bar]), "bar \(bar) is read wrong and not flagged")
        }
        XCTAssertEqual(picture.keySignature, vector.score.keySignature)
        let marks = tempos(picture), page = tempos(vector.score)
        XCTAssertGreaterThanOrEqual(marks.count, 10)
        XCTAssertTrue(Set(marks).isSubset(of: Set(page)), "no tempo is read wrong: \(marks)")
    }

    /// The ePrint Sam sent (#49): two pages printed four times over, read
    /// once. Checked against the printed page by eye on 2026-10-23.
    func testTheArabianDancesEPrint() throws {
        let score = try local("Arabian Dances EPRINT-horn.pdf").score
        let bars = notes(score)
        XCTAssertEqual(score.events.map(\.measure).max(), 96, "the last bar number printed is 96")
        XCTAssertEqual(tempos(score), ["76@1", "160@15"])
        XCTAssertEqual(score.timeSignature.beats, 4)
        XCTAssertEqual(score.timeSignature.unit, 4)
        XCTAssertEqual(bars[2], ["rest 4"], "bars 2 to 14 are the 13 bar rest")
        XCTAssertEqual(bars[14], ["rest 4"])
        XCTAssertEqual(bars[15], ["G4 1", "G4 1", "G4 1", "G4 1"])
        XCTAssertEqual(bars[16], ["C4 4"], "a whole note on a ledger line, tied on")
        XCTAssertEqual(bars[47], ["C4 0.5", "D4 0.5", "E4 2", "F4 1"], "the cautionary naturals")
        XCTAssertEqual(bars[62], ["Bb3 1", "Bb3 2", "Gb4 1"], "after the key change to one flat")
        XCTAssertEqual(bars[63], ["F4 3", "rest 1"])
        XCTAssertEqual(bars[84], ["F4 1", "F4 1", "F4 1", "F4 1"], "Play, after the hand claps")
        // The hand claps are x noteheads, not notes to play on a horn, and
        // their bars are left holding only their rests, which the bar sum
        // check flags. Nothing else on the chart is flagged.
        XCTAssertEqual(score.suspectMeasures, Set(66...82))
    }

    // MARK: - Helpers

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext), "\(name).\(ext) is not in the test bundle")
    }

    private func sampleChart() throws -> URL {
        try XCTUnwrap(SampleChart.url, "the sample chart is not in the app bundle")
    }

    private func local(_ name: String) throws -> (url: URL, score: Score) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/local/\(name)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) is not on this machine; the fixture tests above still ran")
        }
        return (url, try ScoreImporter.readOrThrow(url: url))
    }

    /// Each bar's notes as "name beats", rests as "rest beats", in order.
    private func notes(_ score: Score) -> [Int: [String]] {
        var bars: [Int: [String]] = [:]
        for event in score.events {
            let beats = (event.durationBeats * 1000).rounded() / 1000
            let length = beats == beats.rounded() ? "\(Int(beats))" : "\(beats)"
            bars[event.measure, default: []].append(event.isRest ? "rest \(length)" : "\(event.writtenName) \(length)")
        }
        return bars
    }

    private func differingBars(_ a: [Int: [String]], _ b: [Int: [String]]) -> Set<Int> {
        Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }
    }

    /// A bar's lengths alone, the pitches left out.
    private func rhythm(_ bar: [String]?) -> [String] {
        (bar ?? []).map { $0.split(separator: " ").last.map(String.init) ?? "" }
    }

    /// "76@1" for a quarter, "80@7x1.5" for a dotted quarter: the note a
    /// mark counts in is half of what it says, and a half note read as a
    /// quarter plays the passage at half speed.
    private func tempos(_ score: Score) -> [String] {
        score.tempos.map { "\($0.printed)@\($0.measure)" + ($0.noteQuarters == 1 ? "" : "x\($0.noteQuarters)") }
    }

    /// A vector PDF drawn page by page into an image only PDF at 450 ppi, in a
    /// temporary file the test removes.
    private func drawnAsPicture(_ url: URL) throws -> URL {
        let pages = try XCTUnwrap(CGPDFDocument(url as CFURL)).numberOfPages
        let out = try temporaryPDF(drawing: url, pages: Array(1...pages))
        addTeardownBlock { try? FileManager.default.removeItem(at: out) }
        return out
    }

    /// The given pages of a PDF, each drawn into one picture.
    private func temporaryPDF(drawing source: URL, pages: [Int]) throws -> URL {
        let document = try XCTUnwrap(CGPDFDocument(source as CFURL))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("picture-\(UUID().uuidString).pdf")
        var media = try XCTUnwrap(document.page(at: pages[0])).getBoxRect(.mediaBox)
        let pdf = try XCTUnwrap(CGContext(out as CFURL, mediaBox: &media, nil))
        for number in pages {
            let page = try XCTUnwrap(document.page(at: number))
            var box = page.getBoxRect(.mediaBox)
            let scale = 450.0 / 72
            let w = Int(box.width * scale), h = Int(box.height * scale)
            let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)
            let image = try XCTUnwrap(context.makeImage())
            pdf.beginPage(mediaBox: &box)
            pdf.draw(image, in: box)
            pdf.endPage()
        }
        pdf.closePDF()
        return out
    }

    private func writeImagePDF(to url: URL, pages: Int, draw: (CGContext, CGSize) -> Void) throws {
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &media, nil))
        for _ in 0..<pages {
            let size = CGSize(width: 2550, height: 3300)
            let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                                  bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(origin: .zero, size: size))
            draw(context, size)
            pdf.beginPage(mediaBox: &media)
            pdf.draw(try XCTUnwrap(context.makeImage()), in: media)
            pdf.endPage()
        }
        pdf.closePDF()
    }

    private func drawn(_ text: String, face: String, height: Int) throws -> InkBitmap {
        let size = height * 3
        var gray = [UInt8](repeating: 255, count: size * size)
        gray.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            let font = CTFontCreateWithName(face as CFString, CGFloat(height) * 1.4, nil)
            let attributes = [kCTFontAttributeName as NSAttributedString.Key: font,
                              kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: CGFloat(height), y: CGFloat(height))
            CTLineDraw(line, context)
        }
        return InkBitmap(width: size, height: size, ink: gray.map { $0 < 128 ? 1 : 0 }, scale: 1, pageHeight: 0)
    }

    private func inkBox(_ bitmap: InkBitmap) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        var box: (x0: Int, y0: Int, x1: Int, y1: Int)?
        for y in 0..<bitmap.height { for x in 0..<bitmap.width where bitmap.at(x, y) {
            box = box.map { (min($0.x0, x), min($0.y0, y), max($0.x1, x), max($0.y1, y)) } ?? (x, y, x, y)
        } }
        return box
    }
}
