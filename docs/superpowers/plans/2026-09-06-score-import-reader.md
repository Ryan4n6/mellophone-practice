# Score Import Reader Implementation Plan (phases 1 and 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read a digitally engraved sheet-music PDF into a validated `Score` of pitched, timed events, on device, with no network and no third-party package.

**Architecture:** Four units with one job each. `PDFGlyphReader` walks the PDF content stream and emits positioned glyphs and paths in page coordinates, knowing nothing about music. `MusicFontTable` turns a font name plus a Unicode scalar into a `MusicSymbol`, one table per engraver family. `StaffFitter` groups horizontal paths into five-line staff systems, pure geometry. `ScoreBuilder` holds all the music knowledge and produces a `Score` whose every measure has been checked against the time signature.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, Core Graphics (`CGPDFScanner`, `CGPDFContentStreamCreateWithPage`, `CGPDFDocument`), AVFoundation. No Swift Package Manager dependencies.

**Spec:** `docs/superpowers/specs/2026-09-06-score-import-design.md`

**Issue:** #19

## Global Constraints

- **No network code.** No `URLSession`, no SPM package, no CocoaPods. Everything used here is in the iOS SDK. Violating this breaks the App Store privacy label "Data Not Collected" and issue #2.
- **`ios/project.yml` is the source of truth.** Never hand-edit `Mellophone.xcodeproj`; run `cd ios && xcodegen generate`. Do not touch `CURRENT_PROJECT_VERSION` in the pbxproj.
- **Swift language mode is 5.10, not 6.** Do not add actor isolation to audio paths.
- **No em dashes or en dashes** in code comments, commit messages, docs, or user-facing strings. Use a comma, colon, parentheses, or split the sentence. Ranges use "to".
- **Comments say why, not what.** Match the existing style in `ios/Mellophone/Audio/ScalePlayer.swift` and `ios/MellophoneTests/StaffGeometryTests.swift`: a comment earns its place by recording a decision or a trap, not by restating the line below it.
- **Logging** goes through the existing `Log` (OSLog) with the greppable prefix `[IMPORT]`, plus `FileLog.write` under `#if DEBUG` on failure paths. Every failure path logs; see `ScalePlayer.play` for the pattern.
- **Tests are XCTest**, `@testable import Mellophone`, one file per unit under `ios/MellophoneTests/`.
- **Note range is F#3 to C6.** `Note.named(_:)` returns nil outside it. Do not extend the table.
- Every commit message ends with the two trailer lines used in this repo, and references `(#19)`.

## Test command

```sh
cd ios && xcodebuild -project Mellophone.xcodeproj -scheme Mellophone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData test
```

Filter to one class with `-only-testing:MellophoneTests/<ClassName>`.

## File structure

| File | Responsibility |
|---|---|
| `ios/Mellophone/Import/PageGeometry.swift` | `PlacedGlyph`, `PlacedPath`, `PageGeometry`. Plain data, no behaviour |
| `ios/Mellophone/Import/MusicSymbol.swift` | `MusicSymbol` enum and `NoteValue` |
| `ios/Mellophone/Import/MusicFontTable.swift` | Per-engraver codepoint tables and lookup |
| `ios/Mellophone/Import/PDFGlyphReader.swift` | `CGPDFScanner` walk, page coordinates out |
| `ios/Mellophone/Import/StaffFitter.swift` | Paths to `StaffSystem` |
| `ios/Mellophone/Import/Score.swift` | `ScoreEvent`, `Score`, `Measure` |
| `ios/Mellophone/Import/ScoreBuilder.swift` | All music interpretation |
| `ios/Mellophone/Audio/ToneSequence.swift` | The extracted events-taking buffer renderer |

Why `ScoreBuilder` is one file and not seven: its stages share the staff
geometry and the running accidental state, and splitting them would mean
threading that state through seven initialisers. It is expected to reach roughly
400 lines. If it passes 600, split the rhythm stages out first, since they have
the narrowest interface (paths plus noteheads in, durations out).

---

### Task 1: `MusicSymbol` and `MusicFontTable`

Pure data with no dependencies, so it goes first and everything else can be
written against it.

**Files:**
- Create: `ios/Mellophone/Import/MusicSymbol.swift`
- Create: `ios/Mellophone/Import/MusicFontTable.swift`
- Test: `ios/MellophoneTests/MusicFontTableTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum MusicSymbol`, `struct NoteValue`, `struct MusicFontTable` with
  `static func forFont(_ baseFont: String) -> MusicFontTable?` and
  `func symbol(for scalar: UInt32) -> MusicSymbol`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Mellophone

/// The codepoints here were read out of the real charts in issue #19, not from
/// a specification. Leland is SMuFL; Opus predates SMuFL and uses the legacy
/// Petrucci layout, where the notehead glyphs land on the Latin-1 ligature
/// codepoints. The two tables disagree on every value, which is the whole
/// reason the table is a lookup and not a constant.
final class MusicFontTableTests: XCTestCase {

    func testLelandIsRecognisedAsSMuFL() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("Leland"))
        XCTAssertEqual(t.symbol(for: 0xE0A4), .noteheadBlack)
        XCTAssertEqual(t.symbol(for: 0xE0A3), .noteheadHalf)
        XCTAssertEqual(t.symbol(for: 0xE050), .gClef)
        XCTAssertEqual(t.symbol(for: 0xE260), .flat)
        XCTAssertEqual(t.symbol(for: 0xE261), .natural)
        XCTAssertEqual(t.symbol(for: 0xE262), .sharp)
    }

    func testOpusUsesLegacyPetrucciCodesForTheSameSymbols() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x0153), .noteheadBlack)   // oe ligature
        XCTAssertEqual(t.symbol(for: 0x0152), .noteheadHalf)    // OE ligature
        XCTAssertEqual(t.symbol(for: 0x0077), .noteheadWhole)   // w
        XCTAssertEqual(t.symbol(for: 0x0026), .gClef)           // &
        XCTAssertEqual(t.symbol(for: 0x0062), .flat)            // b
        XCTAssertEqual(t.symbol(for: 0x0023), .sharp)           // #
        XCTAssertEqual(t.symbol(for: 0x006E), .natural)         // n
    }

    /// Subset prefixes ("ABCDEF+Leland") and the Std/Text/Special suffixes
    /// Sibelius uses must all resolve, because that is how they arrive in a
    /// real PDF.
    func testFontNamesAreMatchedLoosely() {
        XCTAssertNotNil(MusicFontTable.forFont("ABCDEF+Leland"))
        XCTAssertNotNil(MusicFontTable.forFont("OpusSpecialStd"))
        XCTAssertNotNil(MusicFontTable.forFont("Maestro"))
        XCTAssertNil(MusicFontTable.forFont("Quicksand-SemiBold"))
        XCTAssertNil(MusicFontTable.forFont("Edwin-Roman"))
    }

    /// Articulations ride a notehead exactly the way an augmentation dot does.
    /// U+02D9 is a staccato dot and U+002E is an augmentation dot, and reading
    /// the first as the second lengthens every staccato note on the page. These
    /// values were measured off PEAK mello.pdf, not guessed.
    func testOpusArticulationsAreNotMistakenForDots() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("OpusStd"))
        XCTAssertEqual(t.symbol(for: 0x003E), .articulation)   // accent
        XCTAssertEqual(t.symbol(for: 0x002D), .articulation)   // tenuto
        XCTAssertEqual(t.symbol(for: 0x005E), .articulation)   // marcato
        XCTAssertEqual(t.symbol(for: 0x02D9), .articulation)   // staccato
        XCTAssertEqual(t.symbol(for: 0x002E), .augmentationDot)
    }

    /// An unrecognised codepoint is retained rather than dropped, so a chart
    /// that defeats the reader can report which glyphs did it.
    func testUnknownScalarsAreRetained() throws {
        let t = try XCTUnwrap(MusicFontTable.forFont("Leland"))
        XCTAssertEqual(t.symbol(for: 0xE999), .unknown(0xE999))
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `-only-testing:MellophoneTests/MusicFontTableTests`
Expected: compile failure, `cannot find 'MusicFontTable' in scope`.

- [ ] **Step 3: Write the implementation**

`ios/Mellophone/Import/MusicSymbol.swift`:

```swift
import Foundation

/// A duration, as a fraction of a whole note, so dotted and tuplet values stay
/// exact instead of accumulating float error across a measure. The measure-sum
/// check in ScoreBuilder compares these for equality, which only works because
/// they are rationals.
struct NoteValue: Equatable, Hashable {
    let numerator: Int
    let denominator: Int

    init(_ numerator: Int, _ denominator: Int) {
        let g = NoteValue.gcd(abs(numerator), abs(denominator))
        self.numerator = numerator / max(g, 1)
        self.denominator = denominator / max(g, 1)
    }

    static let whole = NoteValue(1, 1)
    static let half = NoteValue(1, 2)
    static let quarter = NoteValue(1, 4)
    static let eighth = NoteValue(1, 8)
    static let sixteenth = NoteValue(1, 16)

    /// One augmentation dot adds half again, two adds three quarters again.
    func dotted(_ dots: Int) -> NoteValue {
        var n = self
        var add = self
        for _ in 0..<dots {
            add = NoteValue(add.numerator, add.denominator * 2)
            n = n + add
        }
        return n
    }

    static func + (a: NoteValue, b: NoteValue) -> NoteValue {
        NoteValue(a.numerator * b.denominator + b.numerator * a.denominator,
                  a.denominator * b.denominator)
    }

    /// In beats, given which note value gets the beat (4 = quarter).
    func beats(unit: Int) -> Double {
        Double(numerator) / Double(denominator) * Double(unit)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

/// What a glyph means, independent of which engraver drew it.
enum MusicSymbol: Equatable {
    case noteheadBlack
    case noteheadHalf
    case noteheadWhole
    case gClef
    case fClef
    case sharp
    case flat
    case natural
    case augmentationDot
    case flag(count: Int, up: Bool)
    case rest(NoteValue)
    case timeSigDigit(Int)
    /// Accent, tenuto, marcato, staccato. Carried rather than dropped because
    /// they ride a notehead exactly the way an augmentation dot does, and a
    /// reader that does not know them will read one as a dot and lengthen the
    /// note. ScoreBuilder ignores them; it just must not mistake them.
    case articulation
    case unknown(UInt32)

    var isNotehead: Bool {
        self == .noteheadBlack || self == .noteheadHalf || self == .noteheadWhole
    }

    /// The duration a notehead alone can prove. A black notehead is a quarter
    /// OR ANYTHING SHORTER, and only a flag or a beam decides which, so this
    /// returns the longest it could be and the rhythm stage narrows it.
    var impliedValue: NoteValue? {
        switch self {
        case .noteheadWhole: return .whole
        case .noteheadHalf: return .half
        case .noteheadBlack: return .quarter
        default: return nil
        }
    }
}
```

`ios/Mellophone/Import/MusicFontTable.swift`:

```swift
import Foundation

/// Maps a font's codepoints to musical meaning.
///
/// There are two conventions in the wild and they share no values. SMuFL puts
/// everything in the U+E000 private use area and is what MuseScore's Leland and
/// Bravura use. Everything older inherits Adobe Sonata's layout by way of
/// Petrucci, which parks noteheads on Latin-1 ligature codepoints and clefs on
/// ASCII punctuation; Sibelius's Opus and Finale's Maestro are both that.
///
/// Adding an engraver is adding a table here. It is never a new code path.
struct MusicFontTable {
    private let map: [UInt32: MusicSymbol]

    func symbol(for scalar: UInt32) -> MusicSymbol {
        map[scalar] ?? .unknown(scalar)
    }

    /// Matched by substring because real PDFs carry subset prefixes
    /// ("ABCDEF+Leland") and family suffixes ("OpusSpecialStd").
    static func forFont(_ baseFont: String) -> MusicFontTable? {
        let name = baseFont.contains("+")
            ? String(baseFont.split(separator: "+").last!)
            : baseFont
        if name.contains("Leland") || name.contains("Bravura") || name.contains("MScore") {
            return MusicFontTable(map: smufl)
        }
        if name.contains("Opus") || name.contains("Maestro")
            || name.contains("Petrucci") || name.contains("Sonata") {
            return MusicFontTable(map: petrucci)
        }
        return nil
    }

    private static let smufl: [UInt32: MusicSymbol] = [
        0xE0A2: .noteheadWhole, 0xE0A3: .noteheadHalf, 0xE0A4: .noteheadBlack,
        0xE050: .gClef, 0xE062: .fClef,
        0xE260: .flat, 0xE261: .natural, 0xE262: .sharp,
        0xE1E7: .augmentationDot,
        0xE240: .flag(count: 1, up: true), 0xE241: .flag(count: 1, up: false),
        0xE242: .flag(count: 2, up: true), 0xE243: .flag(count: 2, up: false),
        0xE4E3: .rest(.whole), 0xE4E4: .rest(.half),
        0xE4E5: .rest(.quarter), 0xE4E6: .rest(.eighth), 0xE4E7: .rest(.sixteenth),
        0xE080: .timeSigDigit(0), 0xE081: .timeSigDigit(1), 0xE082: .timeSigDigit(2),
        0xE083: .timeSigDigit(3), 0xE084: .timeSigDigit(4), 0xE085: .timeSigDigit(5),
        0xE086: .timeSigDigit(6), 0xE087: .timeSigDigit(7), 0xE088: .timeSigDigit(8),
        0xE089: .timeSigDigit(9),
    ]

    private static let petrucci: [UInt32: MusicSymbol] = [
        0x0077: .noteheadWhole,      // w
        0x0152: .noteheadHalf,       // OE ligature
        0x0153: .noteheadBlack,      // oe ligature
        0x0026: .gClef,              // &
        0x003F: .fClef,              // ?
        0x0062: .flat,               // b
        0x006E: .natural,            // n
        0x0023: .sharp,              // #
        0x002E: .augmentationDot,    // .  sits to the RIGHT of a notehead
        // Measured against PEAK mello.pdf rather than guessed: each of these
        // rides a notehead (98% to 100% of occurrences share a notehead's x)
        // and sits outside the staff. An earlier draft of this table had none
        // of them, so they fell through to .unknown, and U+02D9 in particular
        // would have been read as a second augmentation dot and lengthened
        // every staccato note on the page.
        0x003E: .articulation,       // >   accent,   105 occurrences
        0x002D: .articulation,       // -   tenuto,    63
        0x02D9: .articulation,       // dot above, staccato, 50
        0x005E: .articulation,       // ^   marcato,   35
        0x006A: .flag(count: 1, up: true),   // j
        0x004A: .flag(count: 1, up: false),  // J
        0x2211: .rest(.quarter),     // summation sign
        0x00CE: .rest(.whole), 0x00CF: .rest(.half),
        0x0030: .timeSigDigit(0), 0x0031: .timeSigDigit(1), 0x0032: .timeSigDigit(2),
        0x0033: .timeSigDigit(3), 0x0034: .timeSigDigit(4), 0x0035: .timeSigDigit(5),
        0x0036: .timeSigDigit(6), 0x0037: .timeSigDigit(7), 0x0038: .timeSigDigit(8),
        0x0039: .timeSigDigit(9),
    ]
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `-only-testing:MellophoneTests/MusicFontTableTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Regenerate the project and commit**

The new files are in a new directory, so XcodeGen has to pick them up.

```sh
cd ios && xcodegen generate && cd ..
git add ios/Mellophone/Import ios/MellophoneTests/MusicFontTableTests.swift ios/Mellophone.xcodeproj
git commit -m "feat(import): codepoint tables for SMuFL and Petrucci engravers (#19)"
```

**The digits are a trap, and Task 4 has to handle it.** `U+0030` to `U+0039`
are mapped to `timeSigDigit` here, but in `PEAK mello.pdf` those same glyphs
appear 35 times sharing a notehead's x and sitting BELOW the staff. Those are not
time signatures, they are measure numbers and tuplet numbers. A time signature
digit is identifiable only by POSITION: inside the staff, at the head of a
system, immediately after the clef and the key signature, and sharing its x with
no notehead. `MusicFontTable` cannot tell them apart and must not try. Task 4
does, and if it gets this wrong every measure fails the sum check and the
validator becomes noise instead of signal.

Still uncertain after measurement, and left as `.unknown` deliberately rather
than guessed: `U+2030` (32 occurrences, 87% on a notehead's x), `U+00D3` (17,
82% on a notehead's x, and its page 1 instances land at four different y bands
including one INSIDE the first staff system, which rules out the tempo-mark
reading) and `U+2211` (9, staff centred, mapped to a quarter rest above on the
strength of the Petrucci convention alone).

Geometry took these as far as it can and no further. Task 5 settles them the
only honest way, by rendering the page at the glyph's coordinates and looking at
it. Do not promote a guess into the table: a wrong rest injects silence that is
not in the music, and a wrong duration desynchronises every note after it.

---

### Task 2: `PageGeometry` and `PDFGlyphReader`

The riskiest task, because `CGPDFScanner`'s callbacks are C function pointers
that cannot capture context.

**Files:**
- Create: `ios/Mellophone/Import/PageGeometry.swift`
- Create: `ios/Mellophone/Import/PDFGlyphReader.swift`
- Test: `ios/MellophoneTests/PDFGlyphReaderTests.swift`

**Interfaces:**
- Consumes: `MusicFontTable` (Task 1), only to decide which fonts to keep.
- Produces: `struct PlacedGlyph { scalar: UInt32; x, y, size: Double; font: String }`,
  `struct PlacedPath { vertices: [CGPoint]; filled: Bool; bounds: CGRect }`,
  `struct PageGeometry { glyphs: [PlacedGlyph]; paths: [PlacedPath] }`,
  `enum PDFGlyphReader { static func read(page: CGPDFPage) -> PageGeometry }`.

- [ ] **Step 1: Write the failing test**

The test builds its own PDF with Core Graphics so it needs no fixture file and
no notation software. Helvetica stands in for a music font here; this test is
about operator walking and coordinates, not about music.

```swift
import XCTest
import CoreGraphics
@testable import Mellophone

/// The reader is tested against a PDF this test draws itself, so the expected
/// coordinates are known exactly rather than measured off someone's export.
/// Nothing here is musical on purpose: PDFGlyphReader must not know what a
/// notehead is.
final class PDFGlyphReaderTests: XCTestCase {

    /// Draw two strings and two filled rectangles at known places.
    private func makeTestPDF() throws -> CGPDFPage {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))

        // A thin wide bar at y=100 and a thick short one at y=200.
        ctx.fill(CGRect(x: 50, y: 100, width: 300, height: 1))
        ctx.fill(CGRect(x: 60, y: 200, width: 20, height: 8))

        ctx.selectFont(name: "Helvetica", size: 12, encoding: .macRoman)
        ctx.setTextDrawingMode(.fill)
        ctx.showText(at: CGPoint(x: 30, y: 250), text: "AB")

        ctx.endPDFPage()
        ctx.closePDF()

        let provider = CGDataProvider(data: data as CFData)!
        let doc = try XCTUnwrap(CGPDFDocument(provider))
        return try XCTUnwrap(doc.page(at: 1))
    }

    func testFindsFilledPathsWithCorrectBounds() throws {
        let g = PDFGlyphReader.read(page: try makeTestPDF())
        let wide = g.paths.filter { $0.filled && $0.bounds.width > 100 }
        XCTAssertEqual(wide.count, 1)
        XCTAssertEqual(wide[0].bounds.minY, 100, accuracy: 0.5)
        XCTAssertEqual(wide[0].bounds.height, 1, accuracy: 0.5)

        let thick = g.paths.filter { $0.filled && $0.bounds.height > 5 }
        XCTAssertEqual(thick.count, 1)
        XCTAssertEqual(thick[0].bounds.minX, 60, accuracy: 0.5)
    }

    func testFindsGlyphsWithCorrectPositions() throws {
        let g = PDFGlyphReader.read(page: try makeTestPDF())
        XCTAssertEqual(g.glyphs.count, 2, "two characters were drawn")
        let first = try XCTUnwrap(g.glyphs.first)
        XCTAssertEqual(first.x, 30, accuracy: 1.0)
        XCTAssertEqual(first.y, 250, accuracy: 1.0)
        XCTAssertEqual(first.size, 12, accuracy: 0.1)
        // The second character must be to the right of the first, which is the
        // only thing that proves Tj advanced the text position at all.
        XCTAssertGreaterThan(g.glyphs[1].x, first.x)
    }

    /// A page with nothing on it must come back empty rather than crash, since
    /// a title page in a real chart is exactly this.
    func testEmptyPageYieldsEmptyGeometry() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
        let doc = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        let g = PDFGlyphReader.read(page: try XCTUnwrap(doc.page(at: 1)))
        XCTAssertTrue(g.glyphs.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `-only-testing:MellophoneTests/PDFGlyphReaderTests`
Expected: compile failure, `cannot find 'PDFGlyphReader' in scope`.

- [ ] **Step 3: Write `PageGeometry.swift`**

```swift
import CoreGraphics

/// One glyph, resolved to page coordinates.
///
/// `scalar` is Unicode, already mapped through the font's ToUnicode CMap, so
/// consumers never see glyph ids. `font` is the BaseFont name with any subset
/// prefix intact, because MusicFontTable does the loose matching.
struct PlacedGlyph {
    let scalar: UInt32
    let x: Double
    let y: Double
    let size: Double
    let font: String
}

/// One path, resolved to page coordinates.
///
/// Deliberately uninterpreted. A staff line, a stem, a beam, a barline, a ledger
/// line, a slur and a hairpin are all paths, and telling them apart is a music
/// question that belongs in ScoreBuilder, not here.
struct PlacedPath {
    let vertices: [CGPoint]
    let filled: Bool
    let bounds: CGRect
}

struct PageGeometry {
    let glyphs: [PlacedGlyph]
    let paths: [PlacedPath]

    static let empty = PageGeometry(glyphs: [], paths: [])
}
```

- [ ] **Step 4: Write `PDFGlyphReader.swift`**

```swift
import CoreGraphics
import Foundation

/// Walks a PDF page's content stream and reports where everything is.
///
/// CGPDFScanner's callbacks are @convention(c), so they cannot capture. State
/// travels through the scanner's info pointer as an unretained reference to a
/// class instance, which is why State is a class and why the caller must keep
/// it alive across the scan. Getting this wrong does not crash, it silently
/// reports an empty page.
enum PDFGlyphReader {

    private final class State {
        var ctm: [CGAffineTransform] = []
        var current = CGAffineTransform.identity
        var textMatrix = CGAffineTransform.identity
        var lineMatrix = CGAffineTransform.identity
        var fontSize: Double = 0
        var fontKey: String = ""
        var fonts: [String: (name: String, toUnicode: [UInt32: UInt32])] = [:]
        var pending: [CGPoint] = []
        var glyphs: [PlacedGlyph] = []
        var paths: [PlacedPath] = []
    }

    static func read(page: CGPDFPage) -> PageGeometry {
        let state = State()
        state.fonts = FontResources.read(from: page)

        let table = CGPDFOperatorTableCreate()!
        defer { CGPDFOperatorTableRelease(table) }
        install(into: table)

        let info = Unmanaged.passUnretained(state).toOpaque()
        let stream = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(stream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)

        Log.import_.info("[IMPORT] page read: \(state.glyphs.count, privacy: .public) glyphs, \(state.paths.count, privacy: .public) paths")
        return PageGeometry(glyphs: state.glyphs, paths: state.paths)
    }
}
```

One callback, in full, because the info-pointer dance is the thing that goes
wrong and it goes wrong silently:

```swift
private static func install(into table: CGPDFOperatorTable) {
    // The callback is @convention(c) and cannot capture, so State arrives
    // through the info pointer. passUnretained is correct ONLY because read()
    // holds a strong reference for the whole scan.
    CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
        guard let info else { return }
        let state = Unmanaged<State>.fromOpaque(info).takeUnretainedValue()
        var v = [CGPDFReal](repeating: 0, count: 6)
        // Operands pop in reverse order. Popping them in source order yields a
        // transposed matrix that looks almost right, which is why this is a
        // countdown and not a loop upward.
        for i in stride(from: 5, through: 0, by: -1) {
            guard CGPDFScannerPopNumber(scanner, &v[i]) else { return }
        }
        state.current = CGAffineTransform(a: v[0], b: v[1], c: v[2],
                                          d: v[3], tx: v[4], ty: v[5])
            .concatenating(state.current)
    }
}
```

The remaining callbacks follow the same shape. Implement, in this order, and add one callback at a time running the test
after each so a wrong info-pointer cast surfaces immediately:

1. `q` / `Q` / `cm` maintaining `state.current` and the stack.
2. `BT` / `ET` / `Tf` / `Tm` / `Td` / `TD` / `T*` maintaining `textMatrix` and
   `lineMatrix`.
3. `Tj` / `TJ` / `'` / `"`, decoding each two-byte code through the font's
   ToUnicode map, emitting a `PlacedGlyph` at `textMatrix.concatenating(current)`
   applied to the origin, then advancing `textMatrix` by the glyph width. Widths
   come from the font's `/W` array; where absent, advance by `0.5 * fontSize`,
   which is enough for the ordering the tests assert and is never used for
   pitch.
4. `m` / `l` / `c` / `v` / `y` / `h` / `re` accumulating `state.pending`.
5. `f` / `f*` / `F` / `B` / `B*` / `S` / `s` / `n` flushing `pending` into a
   `PlacedPath` with `filled` set for the `f` and `B` family, and clearing it.

Add a nested `FontResources` enum that reads the page dictionary's
`/Resources /Font`, and for each entry pulls `/BaseFont` and parses the
`/ToUnicode` CMap stream's `beginbfrange` and `beginbfchar` sections into
`[UInt32: UInt32]`. Both charts in issue #19 use a single `beginbfrange` with an
array form; support `beginbfchar` too, because Finale emits it.

Add `import_` to `Log` in `ios/Mellophone/App/Log.swift`, following the existing
category pattern.

- [ ] **Step 5: Run the test and verify it passes**

Run: `-only-testing:MellophoneTests/PDFGlyphReaderTests`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```sh
cd ios && xcodegen generate && cd ..
git add ios/Mellophone/Import ios/Mellophone/App/Log.swift ios/MellophoneTests/PDFGlyphReaderTests.swift ios/Mellophone.xcodeproj
git commit -m "feat(import): walk a PDF content stream into positioned glyphs and paths (#19)"
```

---

### Task 3: `StaffFitter`

**Files:**
- Create: `ios/Mellophone/Import/StaffFitter.swift`
- Test: `ios/MellophoneTests/StaffFitterTests.swift`

**Interfaces:**
- Consumes: `PlacedPath` (Task 2).
- Produces: `struct StaffSystem` with STORED `lineYs: [Double]` and
  `xRange: ClosedRange<Double>`, and COMPUTED `topLineY` and `halfSpace`, plus
  `enum StaffFitter { static func systems(in paths: [PlacedPath]) -> [StaffSystem] }`.

**Corrected during execution.** Three things in the first draft of this task
were wrong, and all three are recorded here because the reasons outlive the
code:

1. It called `Log.import_`, which does not exist. The logger is `Log.score`.
2. Its `rule()` test helper built the rect with its ORIGIN at y, so every
   `midY` came out 0.35 points below the position the test then asserted. The
   helper now centres the rect on y, which is also what a drawn line does.
3. It sorted every wide thin path on the page by y and took each five in a row.
   That finds 6 systems on a PEAK mello.pdf page that has 9, because a
   multi-measure rest H-bar is wide, thin, drawn twice (stroked and filled) and
   sits BETWEEN two staff lines, so it takes a slot inside the staff and makes
   the spacing look uneven. The fix is to group rules by x extent first: the
   five lines of a system are one set of rectangles and share their ends
   exactly, while the H-bars are 45 to 78 points wide against 517.1 for a line.
   Measured after the fix: 9, 10 and 10 systems on pages 1 to 3, accounting for
   every wide thin path on each page.

**Corrected again while executing Task 4.** Grouping by x extent, which is what
fixed Sibelius, breaks MuseScore, and the naming was wrong for both:

4. MuseScore emits a fresh set of five rules FOR EVERY MEASURE, so one physical
   staff arrives as many x-extent groups. Measured on
   `Florida Fight Song (Orange and Blue)-Horn in F.pdf` page 1: 27 systems where
   the page has 4, fragmented into segments 43 to 105 points wide that abut
   exactly (one ends at 180.2 and the next begins at 180.2). Every downstream
   stage breaks on that, because the clef and the key signature live only in the
   leftmost fragment. The fix is a merge pass after the fit: systems whose
   `lineYs` agree within half a point are one staff, and their x ranges union.
   Measured after the fix: Florida 27 to 4, PEAK 9 to 9 (unchanged, since
   Sibelius draws each staff as one rule set).
5. `topLineY` returned the SMALLEST y, which in a PDF is the BOTTOM line. PDF
   user space has y increasing upward and `PDFGlyphReader` reports raw user
   space. Renamed `bottomLineY`, and `systems(in:)` now sorts descending so that
   `systems[0]` is the top staff on the page. See the coordinate note in Task 4
   for the measurement that settles the direction.

- [x] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import Mellophone

/// Real numbers: the MuseScore chart in issue #19 puts its five lines at
/// 360.50, 365.46, 370.42, 375.38 and 380.34, a spacing of 4.96 that is even to
/// within rounding. Those are the values used here.
///
/// Nothing in this file is musical. StaffFitter is pure geometry, which is what
/// lets these tests be written with made-up rectangles instead of a fixture.
final class StaffFitterTests: XCTestCase {

    /// A rule CENTRED on `y`, because a line drawn at y with thickness h spans
    /// y plus or minus h/2. An earlier version of this helper built the rect
    /// with its ORIGIN at y, which put every midY 0.35 points low and made the
    /// asserted line positions wrong rather than the fitter wrong.
    private func rule(y: Double, x0: Double = 50, x1: Double = 500, h: Double = 0.7) -> PlacedPath {
        let r = CGRect(x: x0, y: y - h / 2, width: x1 - x0, height: h)
        return PlacedPath(vertices: [CGPoint(x: x0, y: y), CGPoint(x: x1, y: y)],
                          filled: true, bounds: r)
    }

    func testFiveEvenlySpacedRulesBecomeOneSystem() {
        let paths = [360.50, 365.46, 370.42, 375.38, 380.34].map { rule(y: $0) }
        let systems = StaffFitter.systems(in: paths)
        XCTAssertEqual(systems.count, 1)
        XCTAssertEqual(systems[0].topLineY, 360.50, accuracy: 0.01)
        XCTAssertEqual(systems[0].halfSpace, 2.48, accuracy: 0.01)
    }

    func testTwoSystemsOnOnePageAreSeparated() {
        let a = [360.50, 365.46, 370.42, 375.38, 380.34]
        let b = [472.10, 477.06, 482.02, 486.98, 491.94]
        let systems = StaffFitter.systems(in: (a + b).map { rule(y: $0) })
        XCTAssertEqual(systems.count, 2)
        XCTAssertEqual(systems[0].topLineY, 360.50, accuracy: 0.01)
        XCTAssertEqual(systems[1].topLineY, 472.10, accuracy: 0.01)
    }

    /// Four lines is not a staff, and neither is five with a gap in the middle.
    /// Refusing both is what keeps text underlines and bracket lines out of the
    /// result.
    func testRejectsGroupsThatAreNotFiveEvenLines() {
        XCTAssertTrue(StaffFitter.systems(in: [360.5, 365.46, 370.42, 375.38].map { rule(y: $0) }).isEmpty)
        let uneven = [360.5, 365.46, 370.42, 379.0, 384.0].map { rule(y: $0) }
        XCTAssertTrue(StaffFitter.systems(in: uneven).isEmpty)
    }

    /// Sibelius STROKES its staff lines and MuseScore fills them. A stroked line
    /// arrives with bounds of exactly zero height, so a thickness test that
    /// excludes 0, or a filter that requires `filled`, finds no staff at all on
    /// every chart Sam actually owns. Measured on PEAK mello.pdf: 248 stroked
    /// paths against 70 filled, and of the 57 wide thin paths on one page only
    /// 6 are fills.
    func testFindsStrokedStaffLinesAsWellAsFilled() {
        let stroked = [360.50, 365.46, 370.42, 375.38, 380.34].map {
            PlacedPath(vertices: [CGPoint(x: 50, y: $0), CGPoint(x: 500, y: $0)],
                       filled: false,
                       bounds: CGRect(x: 50, y: $0, width: 450, height: 0))
        }
        let systems = StaffFitter.systems(in: stroked)
        XCTAssertEqual(systems.count, 1, "a stroked staff is still a staff")
        XCTAssertEqual(systems[0].topLineY, 360.50, accuracy: 0.01)
    }

    /// A beam is a filled path too, and it is short and thick. Neither it nor a
    /// stem may be mistaken for a staff line.
    func testIgnoresShortAndThickPaths() {
        var paths = [360.50, 365.46, 370.42, 375.38, 380.34].map { rule(y: $0) }
        paths.append(rule(y: 362.0, x0: 100, x1: 118, h: 3.5))   // a beam
        paths.append(rule(y: 371.0, x0: 200, x1: 201, h: 24))    // a stem
        let systems = StaffFitter.systems(in: paths)
        XCTAssertEqual(systems.count, 1)
        XCTAssertEqual(systems[0].lineYs.count, 5)
    }

    /// The x span is the playable width of the system: ScoreBuilder uses it to
    /// decide which glyphs belong to which staff when two systems overlap in y
    /// on a two-part page.
    func testReportsTheHorizontalSpanOfTheSystem() {
        let paths = [360.50, 365.46, 370.42, 375.38, 380.34].map { rule(y: $0, x0: 62, x1: 540) }
        let system = StaffFitter.systems(in: paths).first
        XCTAssertEqual(system?.xRange.lowerBound ?? 0, 62, accuracy: 0.01)
        XCTAssertEqual(system?.xRange.upperBound ?? 0, 540, accuracy: 0.01)
    }

    /// Some engravers emit a fill AND a stroke for the same rule. Ten paths at
    /// five y values must still be one staff: without collapsing them, every
    /// five-wide window contains a zero gap, no window is ever even, and a
    /// perfectly ordinary staff is reported as missing.
    func testTheSameLineDrawnTwiceIsStillOneLine() {
        let ys = [360.50, 365.46, 370.42, 375.38, 380.34]
        let doubled = ys.map { rule(y: $0) } + ys.map { rule(y: $0 + 0.1, h: 0) }
        let systems = StaffFitter.systems(in: doubled)
        XCTAssertEqual(systems.count, 1)
        XCTAssertEqual(systems[0].lineYs.count, 5)
        XCTAssertEqual(systems[0].halfSpace, 2.48, accuracy: 0.05)
    }

    /// The bug the unit tests could not have found, caught by running the fitter
    /// over Sam's actual chart. A multi-measure rest is an H-bar drawn BETWEEN
    /// two staff lines, wide enough to pass a width filter, and PEAK mello.pdf
    /// draws each one twice, once stroked and once filled. Sorting the page by y
    /// and taking every five consecutive rules puts that H-bar in a slot inside
    /// the staff, so its spacing looks uneven and the staff is discarded: 6
    /// systems found on a page that has 9.
    ///
    /// What separates them is the x extent. The five lines of a system are one
    /// set of rectangles and share their ends exactly; the H-bars here are 45 to
    /// 78 points wide against 517.1 for a line.
    func testAnHBarInsideTheStaffDoesNotBreakIt() {
        let lines = [207.76, 212.37, 216.97, 221.58, 226.18].map { rule(y: $0, x0: 52.5, x1: 569.6) }
        let hBar = [rule(y: 211.22, x0: 204.7, x1: 268.6, h: 0),
                    rule(y: 211.22, x0: 204.7, x1: 268.6, h: 0)]   // stroked, then filled
        let systems = StaffFitter.systems(in: lines + hBar)
        XCTAssertEqual(systems.count, 1, "the H-bar is not a staff line")
        XCTAssertEqual(systems[0].topLineY, 207.76, accuracy: 0.01)
        XCTAssertEqual(systems[0].halfSpace, 2.303, accuracy: 0.01)
    }

    /// Two H-bars side by side at the same y are two different bars, not one bar
    /// drawn twice. Collapsing on y alone would throw one away, which is why the
    /// duplicate check runs inside an extent group and not across the page.
    func testTwoBarsAtTheSameHeightAreNotDuplicates() {
        let lines = [466.70, 471.31, 475.91, 480.52, 485.13].map { rule(y: $0, x0: 52.5, x1: 569.6) }
        let bars = [rule(y: 481.67, x0: 233.0, x1: 284.6, h: 0),
                    rule(y: 481.67, x0: 285.7, x1: 337.3, h: 0)]
        XCTAssertEqual(StaffFitter.systems(in: lines + bars).count, 1)
    }

    /// Systems are reported top to bottom whichever order their extent groups
    /// were discovered in, because ScoreBuilder reads a page in that order.
    func testSystemsComeBackInPageOrder() {
        let indented = [143.13, 147.74, 152.34, 156.95, 161.55].map { rule(y: $0, x0: 92.0, x1: 569.6) }
        let normal = [78.65, 83.26, 87.86, 92.47, 97.07].map { rule(y: $0, x0: 52.5, x1: 569.6) }
        let systems = StaffFitter.systems(in: indented + normal)
        XCTAssertEqual(systems.count, 2, "an indented first system is still a system")
        XCTAssertEqual(systems[0].topLineY, 78.65, accuracy: 0.01)
        XCTAssertEqual(systems[1].topLineY, 143.13, accuracy: 0.01)
    }

    func testNoPathsYieldsNoSystems() {
        XCTAssertTrue(StaffFitter.systems(in: []).isEmpty)
    }
}
```

- [x] **Step 2: Run the test and verify it fails**

Expected: compile failure, `cannot find 'StaffFitter' in scope`. Confirmed, 8
occurrences.

- [x] **Step 3: Write the implementation**

```swift
import CoreGraphics
import Foundation

/// One five-line staff, in page coordinates.
///
/// Pure geometry. There is no musical vocabulary in this file at all, which is
/// what lets it be tested with made-up rectangles instead of a fixture, and what
/// keeps the question "which line is this note on" in ScoreBuilder where it
/// belongs.
struct StaffSystem {
    /// The five line centres, top to bottom in PDF y order.
    let lineYs: [Double]
    /// The horizontal span of the staff, used to decide which glyphs belong to
    /// it when two systems overlap in y on a multi-part page.
    let xRange: ClosedRange<Double>

    var topLineY: Double { lineYs[0] }

    /// Half the gap between adjacent lines. One diatonic step is exactly this,
    /// because a step moves a notehead from a line to the space beside it, so
    /// every pitch calculation downstream is expressed in these units.
    var halfSpace: Double { (lineYs[4] - lineYs[0]) / 8 }
}

enum StaffFitter {
    /// A staff line is long, thin and horizontal. These thresholds are in PDF
    /// points and were measured against the charts in issue #19, where lines run
    /// several hundred points wide (517.1 in PEAK mello.pdf) and no more than
    /// one point thick, while beams are under twenty wide and over three thick.
    private static let minimumWidth: Double = 40
    /// Admits 0 on purpose: a STROKED line has no area, so its bounds have no
    /// height at all. Sibelius strokes its staff lines and MuseScore fills them,
    /// and an implementation that requires a fill, or a thickness strictly
    /// greater than zero, finds six candidates on a PEAK mello.pdf page that has
    /// fifty and then reports "no staff found" for every chart Sam owns.
    private static let maximumThickness: Double = 2.0
    /// Spacing across the five lines of one staff must agree to this, in points.
    /// The observed variation in a real export is under 0.05.
    private static let spacingTolerance: Double = 0.4
    /// Two rules whose ends agree this closely were drawn by the same rectangle
    /// set, so they belong to the same staff. See `groupedByExtent`.
    private static let extentTolerance: Double = 1.0
    /// Two rules in one extent group closer together in y than this are the same
    /// line drawn twice, not two lines. See `collapsingDuplicates`.
    private static let duplicateEpsilon: Double = 0.5

    static func systems(in paths: [PlacedPath]) -> [StaffSystem] {
        // Deliberately NOT filtering on `filled`. See maximumThickness above.
        let candidates = paths
            .filter { Double($0.bounds.width) >= minimumWidth
                && Double($0.bounds.height) <= maximumThickness }
            .sorted { $0.bounds.midY < $1.bounds.midY }

        // Group before scanning, because sorting the whole page by y interleaves
        // the staff lines with anything else long and thin that happens to sit
        // between them. See groupedByExtent.
        var systems = groupedByExtent(candidates)
            .filter { $0.count >= 5 }
            .flatMap { evenlySpacedRuns(in: collapsingDuplicates($0)) }
        systems.sort { $0.topLineY < $1.topLineY }

        if systems.isEmpty {
            // The failure that matters: a page full of long thin paths that
            // never grouped into fives means the thresholds are wrong for this
            // engraver, which is a different problem from a page with no staff
            // on it, and the counts are what tell them apart.
            Log.score.error(
                "[IMPORT] no staff systems fitted from \(candidates.count, privacy: .public) rules of \(paths.count, privacy: .public) paths")
        } else {
            Log.score.info(
                "[IMPORT] fitted \(systems.count, privacy: .public) staff systems from \(candidates.count, privacy: .public) rules, halfSpace \(systems[0].halfSpace, privacy: .public)")
        }
        return systems
    }

    /// Buckets rules that start and end at the same x.
    ///
    /// The five lines of a system are emitted as one set of rectangles, so they
    /// share an x extent exactly, and nothing else on the page does. This is the
    /// filter that separates a staff line from a multi-measure rest H-bar, which
    /// is the intruder that actually appears in Sam's charts: PEAK mello.pdf
    /// draws its H-bars 45 to 78 points wide, twice each (once stroked, once
    /// filled), sitting BETWEEN two staff lines. Sorting the page by y and
    /// taking every five consecutive rules therefore finds 6 systems on a page
    /// that has 9, because an H-bar takes a slot inside three of the staves and
    /// makes their spacing look uneven.
    ///
    /// Grouping on the extent rather than on the width alone keeps two systems
    /// of the same width but different indentation apart, which is what the
    /// first system of a piece looks like when it carries an instrument name.
    private static func groupedByExtent(_ rules: [PlacedPath]) -> [[PlacedPath]] {
        var groups: [[PlacedPath]] = []
        for rule in rules {
            let index = groups.firstIndex { group in
                guard let first = group.first else { return false }
                return abs(Double(first.bounds.minX) - Double(rule.bounds.minX)) < extentTolerance
                    && abs(Double(first.bounds.maxX) - Double(rule.bounds.maxX)) < extentTolerance
            }
            if let index { groups[index].append(rule) } else { groups.append([rule]) }
        }
        return groups
    }

    /// Keeps the first of any run of rules in one group sharing a y.
    ///
    /// Every rule in these charts is emitted twice, once as a stroke and once as
    /// a fill of the same rectangle. A duplicated line puts a zero into the gap
    /// list, so no window is ever even and a perfectly ordinary staff is
    /// reported as missing. Safe to do only AFTER grouping by extent, because
    /// two different H-bars can share a y side by side and are not duplicates.
    /// Input must be sorted by midY.
    private static func collapsingDuplicates(_ rules: [PlacedPath]) -> [PlacedPath] {
        var kept: [PlacedPath] = []
        for rule in rules {
            guard let last = kept.last,
                  Double(rule.bounds.midY) - Double(last.bounds.midY) < duplicateEpsilon
            else {
                kept.append(rule)
                continue
            }
        }
        return kept
    }

    /// Walks one group looking for five lines at an even spacing.
    ///
    /// Greedy: on a match the window advances a whole staff, on a miss it
    /// advances one rule, so a stray line costs one step of alignment and not
    /// the rest of the group.
    private static func evenlySpacedRuns(in rules: [PlacedPath]) -> [StaffSystem] {
        var systems: [StaffSystem] = []
        var i = 0
        while i + 4 < rules.count {
            let window = Array(rules[i..<(i + 5)])
            let ys = window.map { Double($0.bounds.midY) }
            let gaps = zip(ys, ys.dropFirst()).map { $1 - $0 }
            let even = (gaps.max()! - gaps.min()!) < spacingTolerance
            // The band rejects a group of five rules that are evenly spaced but
            // are not a staff: text underlines sit far apart, and anything under
            // a point apart is one thick line drawn as several.
            if even, gaps[0] > 1, gaps[0] < 30 {
                let x0 = window.map { Double($0.bounds.minX) }.min()!
                let x1 = window.map { Double($0.bounds.maxX) }.max()!
                systems.append(StaffSystem(lineYs: ys, xRange: x0...x1))
                i += 5
            } else {
                i += 1
            }
        }
        return systems
    }
}
```

- [x] **Step 4: Run the test and verify it passes**

Result: 11 tests, 0 failures.

- [x] **Step 5: Commit**

```sh
cd ios && xcodegen generate && cd ..
git add ios/Mellophone/Import/StaffFitter.swift ios/MellophoneTests/StaffFitterTests.swift ios/Mellophone.xcodeproj
git commit -m "feat(import): group horizontal rules into five-line staff systems (#19)"
```


### Task 4: `Score` model and `ScoreBuilder` pitch

**Files:**
- Create: `ios/Mellophone/Import/Score.swift`
- Create: `ios/Mellophone/Import/ScoreBuilder.swift`
- Modify: `ios/Mellophone/Import/StaffFitter.swift` (see Task 3's second addendum)
- Test: `ios/MellophoneTests/ScoreBuilderPitchTests.swift`

**Interfaces:**
- Consumes: `PageGeometry`, `StaffSystem`, `MusicFontTable`, and `Note` from
  `ios/Mellophone/Model/Note.swift`.
- Produces: `struct ScoreEvent`, `struct Score`,
  `enum ScoreBuilder { static func build(pages: [PageGeometry], font: MusicFontTable) -> Score }`.

**Corrected before execution.** The first draft of this task was written against
a coordinate frame and a note table that the charts in issue #19 do not have.
Five things were wrong, all of them settled by measurement against
`PEAK mello.pdf` (Sibelius, Opus) and
`Florida Fight Song (Orange and Blue)-Horn in F.pdf` (MuseScore, Leland) rather
than by argument. The reasons are recorded here because they outlive the code.

1. **The staff is upside down in the draft.** PDF user space has y increasing
   UPWARD, and `PDFGlyphReader` reports raw user space, so `lineYs[0]` (the
   smallest y) is the BOTTOM line, not the top. The draft's first test asserted
   that `[360.50, 365.46, 370.42, 375.38, 380.34]` reads F5, D5, B4, G4, E4,
   which is exactly backwards. The measurement that settles it: the treble clef
   glyph's origin sits at step 2.00 above `lineYs[0]` in BOTH engravers (Opus
   `U+0026` at y 600.28 against `lineYs[0]` 595.67, halfSpace 2.303; Leland
   `U+E050` at y 700.28 against `lineYs[0]` 695.32, halfSpace 2.480). A treble
   clef sits on G4, which is the second line from the BOTTOM. Confirmed a second
   way by rendering the pages: the staff at y 695 on the Florida page is the one
   carrying the title, the tempo mark and measure 1, and the staff at y 360 is
   measure 36. So a LARGER step is a HIGHER pitch, step 0 is E4 in treble, and
   systems order top of page first by DESCENDING y.
2. **Reading a system head needs the merge from Task 3's addendum.** MuseScore
   fragments a staff into one rule set per measure, so without the merge the
   clef and key signature sit in a different `StaffSystem` from the notes.
3. **`Note.named("G#4")` returns nil, and G#4 is not out of range.** The table in
   `NoteData.swift` stores five sharps (F#3, C#4, F#4, C#5, F#5) and spells
   everything else flat, so G#, D#, A#, E#, B#, Cb and Fb have no row. The draft
   asserted `["G#4", "G#4", "G4"]`, which cannot pass. This is not hypothetical:
   Florida page 1 system 1 has a sharp on the G4 line at x 236.73 against a chord
   at x 247.29, rendered and confirmed by eye. Treating it as out of range would
   grey out and SILENCE a note that the horn plays with 2+3. `ScoreBuilder`
   therefore falls back to the enharmonic spelling the table does hold, and the
   test asserts `["Ab4", "Ab4", "G4"]`.
4. **The written spelling has to survive that fallback.** `ScoreEvent` gains
   `writtenName`, the name as the page spells it, alongside `note`. It costs one
   field, it is already computed, and phase 3 cannot draw the note on a staff
   without it: G#4 sits on the G line and Ab4 sits in the space above.
   `outOfRangeName` stays exactly as the spec defines it.
5. **The key signature is per system, not per score.** PEAK changes key inside
   page 1: system 8 (top of page) carries four flats and system 0 (bottom)
   carries one, which is a key change at measure 65. A single score-wide key
   would transpose every note from bar 65 on. `Score.keySignature` keeps the
   first system's value for display; the builder applies each system's own.

   **Wrong, corrected 2026-10-18 (#39):** per system was not enough either.
   PEAK also changes key in the MIDDLE of a line, four flats to one at bar 28,
   and a per-system key held four flats to the end of that line: every D in
   bars 34 and 35 played as D flat. The key is per POSITION on the staff now,
   read from a run of accidentals that belong to no notehead just after a
   barline.

**Also measured, and used below instead of guessed thresholds:**

| Question | Measurement | Rule |
|---|---|---|
| Which digits are a time signature | PEAK: two `4`s at x 96.16, steps 6.09 and 2.04, both inside the staff. Florida: `2` at step 5.95 and `4` at step 2.01, x 0.65 apart. Measure numbers and multi-measure-rest counts and triplet numbers: step 10.95, 11.10, and below the staff | Inside the staff (step 0 to 8), in the head run, upper digit is the beats |
| Where the key signature ends | PEAK four flats at steps 4, 7, 3, 6 = B, E, A, D, spaced 5.18pt (2.25 half-spaces). Florida bottom system: flat at step 4 then ANOTHER at step 4, 11.96pt later, which is an inline courtesy accidental and not the E a second flat would be | The run must follow the canonical order (flats B E A D G C F, sharps F C G D A E B) and stay within 3.5 half-spaces per step |
| Which accidentals are inline | Florida: sharp 4.26 half-spaces left of its notehead, natural 1.87, both at their notehead's exact y | Nearest notehead to the right within 6 half-spaces at the same step |
| What a barline is | PEAK stroked, width 0.00, steps 0.00 to 8.00. Florida stroked, width 0.00, steps -0.11 to 8.11. Stems in the same band span -2.50 to 4.66 or 2.32 to 10.00. Multi-measure-rest end caps span 2.00 to 6.00 | Both ends within half a step of the staff's own ends |
| Repeat and double barlines | Florida 173.74 and 177.38 (1.47 half-spaces apart), PEAK 233.19 and 235.64 (1.06) | Barlines within 3 half-spaces are one barline |

**Scope.** This task is pitch. Events carry the notehead's `impliedValue`, which
is the longest duration a notehead ALONE can prove, and onsets that simply run in
x order. Rests, flags, beams, dots and ties are Task 5, and the measure-sum
validator is Task 6, so `suspectMeasures` is empty here.

- [x] **Step 1: Fix `StaffFitter` first**

Merge systems whose `lineYs` agree within half a point, union their x ranges,
rename `topLineY` to `bottomLineY`, and sort top of page first. Update
`StaffFitterTests` for the rename and the order. Commit separately: it is a fix
to Task 3's unit, not part of Task 4.

- [x] **Step 2: Write the failing test**

Tests build `PageGeometry` by hand, so this task is independent of Tasks 2 and 3
and can be worked on in parallel with them. The line positions are the real ones
from Florida page 1 and the frame is the corrected one: `lineYs[0]` is the bottom
line, E4 in treble, and step counts upward.

```swift
private let lineYs = [360.52, 365.48, 370.44, 375.40, 380.36]  // E4 G4 B4 D5 F5
```

Cases, each named for what it would catch:

1. `testNotesOnLinesReadUpwardFromE4` : the five line ys read E4, G4, B4, D5, F5.
   This is the test that fails if anyone flips the coordinate frame back.
2. `testNotesOnSpacesReadFACE` : the four space ys read F4, A4, C5, E5.
3. `testKeySignatureAppliesToEveryOctave` : one flat at the B4 line makes both
   B4 and B5 into Bb.
4. `testKeySignatureRunStopsWhenTheOrderBreaks` : a second flat on the B line
   rather than the E line is an inline accidental, not a second key flat. This is
   the Florida bottom system, verbatim.
5. `testFourFlatsReadAsBEAD` : the PEAK head, verbatim, reads as four flats and
   4/4.
6. `testMeasureNumberAboveTheStaffIsNotATimeSignature` : a digit at step 11.10
   leaves the score in 4/4. Without this every measure fails Task 6's sum check.
7. `testInlineAccidentalPersistsToTheBarlineAndNoFurther` : `["Ab4", "Ab4", "G4"]`,
   with `writtenName` `["G#4", "G#4", "G4"]`.
8. `testStackedNoteheadsBecomeTwoVoices` : voice 0 is the HIGHER note, which in
   this frame is the larger y.
9. `testOutOfRangeNoteIsKeptAndNamedRatherThanSilenced` : a notehead 18 steps
   above the bottom line is B6, `note` nil, `isRest` false, `outOfRangeName` "B6".

- [x] **Step 3: Run the test and verify it fails**

Expected: compile failure, `cannot find 'ScoreBuilder' in scope`.

- [x] **Step 4: Write `Score.swift`**

`ScoreEvent` is the spec's struct plus `writtenName` (correction 4 above):

```swift
struct ScoreEvent: Identifiable {
    let id = UUID()
    let note: Note?
    let writtenName: String
    let outOfRangeName: String?
    let onsetBeats: Double
    let durationBeats: Double
    let measure: Int
    let voice: Int

    var isRest: Bool { note == nil && outOfRangeName == nil }
}
```

`Score` is the spec's struct unchanged.

- [x] **Step 5: Write the pitch half of `ScoreBuilder.swift`**

In stages, each with the test above as the gate:

1. Fit systems with `StaffFitter`, then assign each glyph to the system whose
   band its y is NEAREST, capped at 12 half-spaces outside the band. Not "inside
   a band widened by six": PEAK's staves are 20 half-spaces apart edge to edge,
   so a fixed widening leaves a dead zone that swallows ledger-line notes, and
   Florida's are 37 apart, where nearest-wins cannot reach the wrong staff.
2. Read each system's head: the leftmost clef, then the key signature run, then
   the time signature, by the rules in the table above.
3. Attach the remaining accidentals inline, and keep a running table cleared at
   every barline. Key it by diatonic index, letter AND octave, which is the
   actual notation rule.
4. Group noteheads by x rounded to a tenth of a point, sort each group by y
   DESCENDING so voice 0 is the highest note, and take `voiceCount` from the
   largest group.
5. Convert y to a step with `round((y - bottomLineY) / halfSpace)`, anchor it on
   the clef glyph's own step, apply the key signature by letter, then the inline
   accidental, which wins. Look up `Note.named`; on nil, try the enharmonic
   spelling; only if that is also nil is the pitch out of range.

- [x] **Step 6: Run the test and verify it passes**

Expected: PASS, 9 tests.

- [x] **Step 7: Validate against Sam's real charts before calling it done**

A throwaway `MellophoneTests/TEMP_*.swift` over both PDFs, read the numbers,
delete it. Unit tests on hand-built geometry cannot catch a coordinate frame
error, and did not: the frame in the draft above passed every test in the draft.

Done with a standalone `swiftc` harness over the real `Import` sources rather
than a TEMP test, because an `xcodebuild test` cycle is 5 to 10 minutes on this
machine and a `swiftc` cycle is 45 seconds, and `PDFGlyphReader`, `StaffFitter`
and `ScoreBuilder` need nothing from the app but `Log` and `NoteData`. Same
sources, same measurement, twelve times the iterations. Results:

| | Florida (MuseScore, Leland) | PEAK (Sibelius, Opus) |
|---|---|---|
| Pages, systems | 1 page, 4 systems | 4 pages, 9 + 10 + 10 + 2 systems |
| Events | 106 | 300 |
| Key | -1 throughout | -4, then -1 at the m65 change, then 0, then -1 |
| Meter | 2/4 | 4/4, changing to 2/4 on page 2 |
| Voices | 2 (divisi throughout) | 1 |
| Out of range | 0 | 0 |
| Enharmonic fallbacks | G#4 to Ab4, 5 times | Cb5 to B4, twice |

Both fallbacks were rendered and read by eye rather than trusted: the Florida
sharp is on the lower note of a divisi chord whose upper note carries a natural,
and the PEAK Cb is the second note of a written Bb, Cb, Db, Eb run with the flat
sitting at its own notehead's exact step. Measures 2 and 3 of the Florida chart
were checked note for note against the rendered page and agree.

- [x] **Step 8: Commit**

```sh
cd ios && xcodegen generate && cd ..
git add ios/Mellophone/Import ios/MellophoneTests/ScoreBuilderPitchTests.swift ios/Mellophone.xcodeproj
git commit -m "feat(import): read pitch, key signature and inline accidentals off a staff (#19)"
```

---

### Task 5: `ScoreBuilder` rhythm

**The Opus table shipped in Task 1 is wrong in five places, and two of them are
serious.** Settled before any rhythm code was written, by classifying every Opus
codepoint in `PEAK mello.pdf` on structure (does it carry its own stem, what
staff steps does it occupy, and what is its offset from the nearest notehead)
and then rendering the survivors framed identically to their own staff. Task 1
identified these by eye from position histograms alone, which is how a rest and
a notehead that both sit on the middle line came to be swapped.

| Codepoint | Task 1 said | Measured truth | Evidence |
|---|---|---|---|
| `U+0152` | `noteheadHalf` | **quarter rest** | 24 occurrences, ALL at step 4.00, no stem ever. Rendered: the zigzag |
| `U+02D9` | `articulation` (staccato) | **noteheadHalf** | 50 occurrences, 38 with their own stem, spread over 12 staff steps. Rendered: a void oval with a down stem, an accent above and an augmentation dot right |
| `U+2211` | `rest(.quarter)` | **rest(.whole)** | 9, all step 4. Framed against its own staff the bar HANGS BELOW the fourth line |
| `U+00D3` | unmapped | **rest(.half)** | 17, all step 4. Same framing: the bar SITS ON the middle line |
| `U+2030` | unmapped | **rest(.eighth)** | 32, all step 4. Rendered: the hook |
| `U+002E` | `augmentationDot` | **articulation** (staccato) | 64, offset from its notehead by exactly 0.88 half-spaces in x and about 2 in y, above or below. A dot that never moves right is not an augmentation dot |
| `U+2122` | unmapped | **augmentationDot** | 8, offset 4.13 half-spaces right and 1 up, which is where a dot goes for a note on a line |
| `U+0052` | unmapped | **flag(2, down)** | 3, pinned at the notehead's x, 5 half-spaces below, exactly like the single down flag. Rendered: two hooks |
| `U+00CE`, `U+00CF` | whole and half rest | **delete** | Zero occurrences in either chart, and they contradict the two rests measured above. An unverified mapping that injects a wrong duration is worse than an `unknown` the reader can report |

Cost of the two serious ones: `U+0152` turned 24 quarter rests into pitched half
notes on the middle line, and `U+02D9` made 50 half notes invisible, so they
never became events at all. Between them that is most of what a measure sum
would have been asked to explain.

The SMuFL side was put through the same classification against the MuseScore
chart and holds up: every mapped Leland codepoint behaves the way its name says.
Its three unmapped codepoints are `U+E044` (repeat dot, at steps 3 and 5),
`U+E4A1` (accent below) and `U+E522` (a dynamic, at step -8). None is a
duration, so none can lengthen a bar, but map the first two so
`unreadableSymbols` keeps meaning "this defeated the reader".

`PEAK mello.pdf` page 1 also contains triplet brackets, so tuplets are not
optional on Sam's charts.

**A multi-measure rest counts as ONE measure and it is not.** Task 4 numbers
measures by counting barlines, and an H-bar standing for six bars sits between a
single pair of them. Measured on Florida page 1: the reader ends at measure 36
where the engraver prints 36 at the START of the last system, an undercount of
exactly the five bars the opening six-bar rest swallowed. PEAK reports 164
measures against a much higher real count for the same reason. This does not
affect Task 4, which uses the measure only to scope an inline accidental and an
H-bar is one such scope either way, but it makes every measure number the user
sees wrong and it will wreck Task 6's per-measure sum. The count is printed above
the H-bar as a digit glyph, which is one of the three things the digit
qualification already has to tell apart.

**Files:**
- Modify: `ios/Mellophone/Import/ScoreBuilder.swift`
- Test: `ios/MellophoneTests/ScoreBuilderRhythmTests.swift`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: no new public types. `ScoreEvent.durationBeats` becomes correct.

- [x] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import Mellophone

/// Rhythm is the half of this reader with no glyph to lean on: whole and half
/// come off the notehead, flags are glyphs, but BEAMS ARE FILLED PATHS. These
/// tests build the beams as rectangles because that is what they are in the
/// PDF.
final class ScoreBuilderRhythmTests: XCTestCase {

    private let lineYs = [360.50, 365.46, 370.42, 375.38, 380.34]

    func testNoteheadShapeGivesWholeHalfAndQuarter() throws {
        let glyphs = [clef(),
                      head(x: 100, y: 370.42, scalar: 0xE0A2),   // whole
                      head(x: 200, y: 370.42, scalar: 0xE0A3),   // half
                      head(x: 300, y: 370.42, scalar: 0xE0A4)]   // black, unbeamed
        let score = build(glyphs: glyphs, extra: [])
        XCTAssertEqual(score.events.map { $0.durationBeats }, [4, 2, 1])
    }

    /// A single flag on a black notehead is an eighth. Two flags is a
    /// sixteenth.
    func testFlagsShortenTheNote() throws {
        let glyphs = [clef(),
                      head(x: 100, y: 370.42),
                      PlacedGlyph(scalar: 0xE240, x: 104, y: 358, size: 10, font: "Leland"),
                      head(x: 150, y: 370.42),
                      PlacedGlyph(scalar: 0xE242, x: 154, y: 358, size: 10, font: "Leland")]
        let score = build(glyphs: glyphs, extra: [])
        XCTAssertEqual(score.events.map { $0.durationBeats }, [0.5, 0.25])
    }

    /// One beam spanning two stems makes both eighths. This is the case that
    /// cannot be read from glyphs at all.
    func testOneBeamMakesBothNotesEighths() throws {
        let glyphs = [clef(), head(x: 100, y: 370.42), head(x: 120, y: 370.42)]
        let stems = [stem(x: 104, top: 356, bottom: 370.42), stem(x: 124, top: 356, bottom: 370.42)]
        let beam = PlacedPath(vertices: [], filled: true,
                              bounds: CGRect(x: 104, y: 356, width: 20, height: 2.5))
        let score = build(glyphs: glyphs, extra: stems + [beam])
        XCTAssertEqual(score.events.map { $0.durationBeats }, [0.5, 0.5])
    }

    /// Two stacked beams make sixteenths, and the count of beams is the only
    /// thing that distinguishes them.
    func testTwoStackedBeamsMakeSixteenths() throws {
        let glyphs = [clef(), head(x: 100, y: 370.42), head(x: 120, y: 370.42)]
        let stems = [stem(x: 104, top: 356, bottom: 370.42), stem(x: 124, top: 356, bottom: 370.42)]
        let beams = [PlacedPath(vertices: [], filled: true, bounds: CGRect(x: 104, y: 356, width: 20, height: 2.5)),
                     PlacedPath(vertices: [], filled: true, bounds: CGRect(x: 104, y: 360, width: 20, height: 2.5))]
        let score = build(glyphs: glyphs, extra: stems + beams)
        XCTAssertEqual(score.events.map { $0.durationBeats }, [0.25, 0.25])
    }

    /// An augmentation dot adds half the note's value again.
    func testAugmentationDotExtendsTheNote() throws {
        let glyphs = [clef(),
                      head(x: 100, y: 370.42, scalar: 0xE0A3),
                      PlacedGlyph(scalar: 0xE1E7, x: 108, y: 370.42, size: 10, font: "Leland")]
        let score = build(glyphs: glyphs, extra: [])
        XCTAssertEqual(score.events[0].durationBeats, 3.0, accuracy: 0.001)
    }

    /// A rest occupies time and produces an event with no note, because "how
    /// long do I sit out before I come in" is half the value of hearing a
    /// marching part at all.
    func testRestsProduceSilentEventsThatOccupyTime() throws {
        let glyphs = [clef(),
                      head(x: 100, y: 370.42),
                      PlacedGlyph(scalar: 0xE4E5, x: 140, y: 370.42, size: 10, font: "Leland"),
                      head(x: 180, y: 370.42)]
        let score = build(glyphs: glyphs, extra: [])
        XCTAssertEqual(score.events.count, 3)
        XCTAssertTrue(score.events[1].isRest)
        XCTAssertEqual(score.events[2].onsetBeats, 2.0, accuracy: 0.001)
    }

    // MARK: helpers

    private func clef() -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE050, x: 55, y: 375.38, size: 10, font: "Leland")
    }
    private func head(x: Double, y: Double, scalar: UInt32 = 0xE0A4) -> PlacedGlyph {
        PlacedGlyph(scalar: scalar, x: x, y: y, size: 10, font: "Leland")
    }
    private func stem(x: Double, top: Double, bottom: Double) -> PlacedPath {
        PlacedPath(vertices: [], filled: true,
                   bounds: CGRect(x: x, y: top, width: 0.8, height: bottom - top))
    }
    private func build(glyphs: [PlacedGlyph], extra: [PlacedPath]) -> Score {
        let staff = lineYs.map {
            PlacedPath(vertices: [], filled: true,
                       bounds: CGRect(x: 50, y: $0, width: 450, height: 0.7))
        }
        return ScoreBuilder.build(pages: [PageGeometry(glyphs: glyphs, paths: staff + extra)],
                                  font: MusicFontTable.forFont("Leland")!)
    }
}
```

- [x] **Step 2: Run the test and verify it fails**

Expected: FAIL. Durations are all 1.0 because Task 4 leaves them at the
notehead's implied value.

- [x] **Step 3: Implement the rhythm stages**

1. **Stems.** A filled path narrower than one half-space and taller than three,
   whose x is within one half-space of a notehead's x, is that notehead's stem.
   Its far end from the notehead is the stem tip.
2. **Beams.** A filled path thicker than one and a half points, wider than three,
   and whose bounds contain or touch a stem tip, is a beam on that stem. Count
   the distinct beams touching a stem; each one halves the value from a quarter.
   Two stems touched by the same beam path are in the same beam group.
3. **Flags.** A `flag(count:up:)` glyph within one half-space of a stem tip
   applies its count the same way. A note has flags or beams, never both.
4. **Dots.** An `augmentationDot` glyph to the right of a notehead within two
   half-spaces horizontally and half a half-space vertically. Count them and call
   `NoteValue.dotted(_:)`.
5. **Rests.** A `rest(value:)` glyph is an event with `note` nil, placed in the x
   ordering with the noteheads.
6. **Onsets.** Sort every event in a system by x, then accumulate durations from
   zero. Systems concatenate in reading order, pages in order.

Revisit the Petrucci rest and flag codepoints from Task 1 here, against
`PEAK mello.pdf`. The histogram in issue #19 shows `U+003E` 33 times on page 1,
which is far too many for a rest and is almost certainly the accent articulation;
whatever it is, it must not be read as a duration.

- [x] **Step 4: Run the test and verify it passes**

Expected: PASS, 6 tests.

**What shipped, and what it measures.** Tests rewritten in the corrected
coordinate frame from Task 4; 11 cases, all passing. Multi-measure rests were
pulled into this task because they break measure NUMBERING, which is the thing
Task 6 has to trust.

| | MuseScore (Florida) | Sibelius (PEAK) |
|---|---|---|
| Events | 118, 12 of them rests | 534, 208 of them rests |
| Last measure | 41, was 36 before this task | 256 |
| Measures summing to the meter | 39 of 41 | 173 of 256 |
| System spans against the printed measure numbers | n/a, numbers are in a text font | 27 of 31 exact, residual drift +5 |

The Sibelius check is the strong one: that chart prints a measure number above
every system, so the reader's own numbering can be compared against the
engraver's at 31 points. Three of the eight measures it was over by came from
`barlineMergeReach`, which the gap distribution then settled: 49 gaps of 1.0 to
3.0 half-spaces, three at 4.00 to 5.63, then NOTHING until 11.31 and 129 above
12. The threshold belongs in the empty band, so it moved from 3 to 8.

Two scoping bugs found by measuring rather than by the tests: the count-digit
window was written in points while its own comment said half-spaces, and
`stems`, `beams` and the end-cap search were handed the whole page rather than
their own staff, so one system could count the staff below's beams against its
own notes. Neither would have shown up in a unit test built from one staff.

**Deferred to Task 6, deliberately: tuplets.** `PEAK mello.pdf` writes its
triplet numbers as `U+0033` in **OpusTextStd**, the text companion face that
`MusicFontTable.forFont` excludes on purpose, with the bracket drawn as four
short paths (two verticals about 4.75 half-spaces tall, two horizontals about
9.36 wide, sitting outside the staff). So the number is reachable only by
admitting a font that also carries dynamics and tempo text, which is exactly
what the exclusion exists to prevent. The principled version is to detect the
BRACKET geometrically first and then read the digit inside it, the same way a
time signature is qualified by position rather than by codepoint. That belongs
with the validator, because the validator is what shows which bars need it: a
triplet bar read straight is the design's stated "degraded, honest, still
useful" case, and it should arrive at the user flagged rather than silently
wrong.

**Never done in Task 6, done in #39 (2026-10-18).** Flagged was the outcome
for months: 15 of PEAK's 27 suspect bars were triplets once the barline bug
was fixed. The bracket-first idea above held up, with one change: the number
is taken from the PAGE's glyphs (any font) rather than by admitting a text
font into the staff, and a lone digit only counts with a bracket or a beam
where a tuplet number's would be. MuseScore prints its tuplet numbers in
Edwin-Italic, which is also its bar number font, so the geometry is the whole
test. Ties, which this task listed beside flags and beams, were never read
either until #39.

- [x] **Step 5: Commit**

```sh
git add ios/Mellophone/Import/ScoreBuilder.swift ios/MellophoneTests/ScoreBuilderRhythmTests.swift
git commit -m "feat(import): durations from noteheads, flags, beams, dots and rests (#19)"
```

---

### Task 6: The measure-sum validator and its negative control

This is the task that makes the whole reader trustworthy, and it is deliberately
separate so it gets its own review.

**Files:**
- Modify: `ios/Mellophone/Import/ScoreBuilder.swift`
- Test: `ios/MellophoneTests/ScoreValidatorTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `Score.suspectMeasures` populated.

- [x] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import Mellophone

/// The reader is only as trustworthy as this check. It is the same idea as
/// verifyFingerings() re-checking the fingering derivation in the browser on
/// every load, and as check-instruments.js refusing to run when the stored
/// table disagrees: a measure whose durations do not sum to the time signature
/// is a measure the reader got wrong, and it must say so.
///
/// The negative control is the point. A validator nobody has watched fail is
/// not a validator, which is the lesson ScalePitchTests was built on.
final class ScoreValidatorTests: XCTestCase {

    private let lineYs = [360.50, 365.46, 370.42, 375.38, 380.34]

    /// Four quarters in 4/4 sums, so nothing is flagged.
    func testCompleteMeasureIsNotFlagged() {
        let heads = [100.0, 120, 140, 160].map {
            PlacedGlyph(scalar: 0xE0A4, x: $0, y: 370.42, size: 10, font: "Leland")
        }
        let score = build(glyphs: [clef()] + timeSig44() + heads, extra: [barline(x: 200)])
        XCTAssertTrue(score.suspectMeasures.isEmpty)
        XCTAssertEqual(score.events.count, 4)
    }

    /// NEGATIVE CONTROL: three quarters in 4/4 does not sum, and must be caught.
    func testShortMeasureIsFlagged() {
        let heads = [100.0, 120, 140].map {
            PlacedGlyph(scalar: 0xE0A4, x: $0, y: 370.42, size: 10, font: "Leland")
        }
        let score = build(glyphs: [clef()] + timeSig44() + heads, extra: [barline(x: 200)])
        XCTAssertEqual(score.suspectMeasures, [0], "a three-beat measure in 4/4 must be flagged")
    }

    /// NEGATIVE CONTROL: five quarters in 4/4 must be caught too. A validator
    /// that only checks one direction misses every duration read as too short.
    func testOverfullMeasureIsFlagged() {
        let heads = [100.0, 120, 140, 160, 180].map {
            PlacedGlyph(scalar: 0xE0A4, x: $0, y: 370.42, size: 10, font: "Leland")
        }
        let score = build(glyphs: [clef()] + timeSig44() + heads, extra: [barline(x: 200)])
        XCTAssertEqual(score.suspectMeasures, [0])
    }

    /// A good measure next to a bad one must not be flagged with it, or the flag
    /// tells Sam nothing about where to look.
    func testOnlyTheBadMeasureIsFlagged() {
        let good = [100.0, 120, 140, 160]
        let bad = [220.0, 240, 260]
        let heads = (good + bad).map {
            PlacedGlyph(scalar: 0xE0A4, x: $0, y: 370.42, size: 10, font: "Leland")
        }
        let score = build(glyphs: [clef()] + timeSig44() + heads,
                          extra: [barline(x: 200), barline(x: 300)])
        XCTAssertEqual(score.suspectMeasures, [1])
    }

    /// Unrecognised glyphs are reported rather than dropped, so a chart from an
    /// engraver we have no table for can say what beat it.
    func testUnknownSymbolsAreReported() {
        let odd = PlacedGlyph(scalar: 0xE999, x: 100, y: 370.42, size: 10, font: "Leland")
        let score = build(glyphs: [clef()] + timeSig44() + [odd], extra: [])
        XCTAssertTrue(score.unreadableSymbols.contains(0xE999))
    }

    // MARK: helpers

    private func clef() -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE050, x: 55, y: 375.38, size: 10, font: "Leland")
    }
    private func timeSig44() -> [PlacedGlyph] {
        [PlacedGlyph(scalar: 0xE084, x: 75, y: 365.46, size: 10, font: "Leland"),
         PlacedGlyph(scalar: 0xE084, x: 75, y: 375.38, size: 10, font: "Leland")]
    }
    private func barline(x: Double) -> PlacedPath {
        PlacedPath(vertices: [], filled: true,
                   bounds: CGRect(x: x, y: 360.5, width: 0.8, height: 19.84))
    }
    private func build(glyphs: [PlacedGlyph], extra: [PlacedPath]) -> Score {
        let staff = lineYs.map {
            PlacedPath(vertices: [], filled: true,
                       bounds: CGRect(x: 50, y: $0, width: 450, height: 0.7))
        }
        return ScoreBuilder.build(pages: [PageGeometry(glyphs: glyphs, paths: staff + extra)],
                                  font: MusicFontTable.forFont("Leland")!)
    }
}
```

- [x] **Step 2: Run the test and verify it fails**

Expected: FAIL on `testShortMeasureIsFlagged`, since `suspectMeasures` is still
always empty.

- [x] **Step 3: Implement**

Split events at barlines into measures, sum `durationBeats` per measure per
voice, and compare to `beats` from the time signature. Insert the measure index
into `suspectMeasures` when any voice disagrees by more than 0.001. Do not drop
or repair the events; the UI shows them flagged. Log each flagged measure with
`[IMPORT]` and its computed sum, because that number is what tells you which
stage got it wrong.

Two measures are exempt from the check and must not be flagged: the first, when
it is shorter than the time signature, which is a pickup, and the last, for the
same reason.

- [x] **Step 4: Run the test and verify it passes**

Expected: PASS, 5 tests.

- [x] **Step 5: Run the WHOLE suite**

```sh
cd ios && xcodebuild -project Mellophone.xcodeproj -scheme Mellophone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData test
```

Expected: all pre-existing tests still pass. `BeatScheduleTests`,
`ScalePitchTests` and `FingeringChartTests` in particular must be untouched.

**Corrected during execution.**

1. **Sum the TOP VOICE, not every voice.** The draft above flags a measure when
   any voice disagrees. Measured against the divisi chart that flags two extra
   bars, because an engraver writes ONE notehead where a divisi goes briefly to
   unison and the lower voice is then legitimately short. A third rule, summing
   the longest duration at each onset, flags five extra because it double counts
   wherever the lower voice holds through two notes of the upper. Top voice
   alone: 39 of 41. A validator that cries wolf is worse than none, which is the
   same argument as the time signature qualification in Task 4.
2. **Measures are numbered from 1**, as the engraver numbers them, so the test
   expectations are `[1]` and `[2]` and not `[0]`.
3. The pickup exemption needs its own negative control. An OVERFULL first bar is
   not a pickup, and the exemption must not swallow it.

**What running it found, which is the point of building it.** The first run
flagged 83 of PEAK's 256 measures, and 54 of those held exactly 4 beats against
an expected 2. That shape is not a rhythm bug, it is a meter bug, and it was:
**a meter change does not wait for a new system.** The whole document carries
six in-staff time signature digits and FOUR of them are on one staff, 2/4 at
x 212 and back to 4/4 at x 286. Task 4's head reader took the first and applied
it to that staff and every staff after it. Meters are now read anywhere inside
the staff, applied from their own x, and the last one carries forward. Suspect
bars went 83 to 30.

| | MuseScore (Florida) | Sibelius (PEAK) |
|---|---|---|
| Measures | 41 | 256 |
| Flagged | 2 (5%) | 30 (12%) |

The triplets deferred in Task 5 are the known reason for most of what is left.
They now arrive at the user flagged rather than silently wrong, which is exactly
the "degraded, honest, still useful" case the design asks for. Anyone picking up
the tuplet work should start from the flagged list: it localises the bars.

- [x] **Step 6: Commit**

```sh
git add ios/Mellophone/Import/ScoreBuilder.swift ios/MellophoneTests/ScoreValidatorTests.swift
git commit -m "feat(import): flag measures whose durations do not sum to the time signature (#19)"
```

---

### Task 7: Extract the buffer renderer from `ScalePlayer`

A refactor with an existing test suite as its guard, kept separate from the
reader so a failure here is unambiguous.

**Files:**
- Create: `ios/Mellophone/Audio/ToneSequence.swift`
- Modify: `ios/Mellophone/Audio/ScalePlayer.swift`
- Test: `ios/MellophoneTests/ToneSequenceTests.swift`

**Interfaces:**
- Consumes: `TonePlayer.render` (unchanged).
- Produces: `enum ToneSequence` with
  `struct Event { let frequency: Double; let onset: Double; let duration: Double }`
  and `static func render(events: [Event], volume: Double, format: AVAudioFormat) -> AVAudioPCMBuffer?`.

- [x] **Step 1: Write the failing test**

```swift
import XCTest
import AVFoundation
@testable import Mellophone

/// The renderer moved out of ScalePlayer so an imported part with uneven
/// durations can use it. ScalePlayerTests is the regression guard on the move;
/// these tests cover only what is new, which is that onset and duration are now
/// per event.
final class ToneSequenceTests: XCTestCase {

    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    func testBufferIsLongEnoughForTheLastEventToRingOut() throws {
        let events = [ToneSequence.Event(frequency: 440, onset: 0, duration: 0.5),
                      ToneSequence.Event(frequency: 440, onset: 2.0, duration: 1.0)]
        let buffer = try XCTUnwrap(ToneSequence.render(events: events, volume: 0.25, format: format))
        XCTAssertEqual(Double(buffer.frameLength) / 48_000, 3.0, accuracy: 0.01)
    }

    /// Silence where a rest is. The gap between the two events above must be
    /// actually silent, or a rest sounds like a held note.
    func testGapsBetweenEventsAreSilent() throws {
        let events = [ToneSequence.Event(frequency: 440, onset: 0, duration: 0.5),
                      ToneSequence.Event(frequency: 440, onset: 2.0, duration: 1.0)]
        let buffer = try XCTUnwrap(ToneSequence.render(events: events, volume: 0.25, format: format))
        let data = buffer.floatChannelData![0]
        // 1.0s to 1.9s falls entirely in the gap.
        for i in 48_000..<91_200 {
            XCTAssertEqual(data[i], 0, accuracy: 0.0001, "sample \(i) should be silent")
        }
    }

    /// Overlapping releases are summed, then the whole buffer is scaled back if
    /// the sum clipped. Clipping a run is far more audible than it being
    /// slightly quieter, which is why ScalePlayer did this and why it survives
    /// the move.
    func testOverlappingEventsDoNotClip() throws {
        let events = (0..<8).map {
            ToneSequence.Event(frequency: 440, onset: Double($0) * 0.02, duration: 1.0)
        }
        let buffer = try XCTUnwrap(ToneSequence.render(events: events, volume: 1.0, format: format))
        let data = buffer.floatChannelData![0]
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
        XCTAssertLessThanOrEqual(peak, 1.0)
    }

    func testEmptyEventListReturnsNil() {
        XCTAssertNil(ToneSequence.render(events: [], volume: 0.25, format: format))
    }
}
```

- [x] **Step 2: Run the test and verify it fails**

Expected: compile failure, `cannot find 'ToneSequence' in scope`.

- [x] **Step 3: Move the renderer**

Copy the body of `ScalePlayer.render` into `ToneSequence.render`, replacing the
computed `offset = index * interval * sampleRate` with `event.onset * sampleRate`
and the fixed `noteDuration` with `event.duration`. Keep the summing, the peak
scan and the normalisation exactly as they are, and carry their comments across
unchanged: they record why summing beats overwriting.

Then reduce `ScalePlayer.render` to a caller:

```swift
static func render(notes: [Note], interval: Double, volume: Double,
                   format: AVAudioFormat) -> AVAudioPCMBuffer? {
    // 90% of the gap, so notes are separated rather than slurred, matching the
    // web version. The imported-score path passes real durations instead.
    let events = notes.enumerated().map {
        ToneSequence.Event(frequency: $1.frequency,
                           onset: Double($0) * interval,
                           duration: interval * 0.9)
    }
    return ToneSequence.render(events: events, volume: volume, format: format)
}
```

- [x] **Step 4: Run BOTH suites and verify they pass**

```sh
-only-testing:MellophoneTests/ToneSequenceTests -only-testing:MellophoneTests/ScalePlayerTests -only-testing:MellophoneTests/ScalePitchTests
```

Expected: PASS. `ScalePitchTests` measures the fundamental of every rendered note
with a YIN detector, so it is the real proof the move changed no sound.

**Two things are new beyond a straight move**, both about parts rather than
scales, and both have a test:

1. The buffer is sized from the LATEST ENDING event rather than from the last
   one in the list. A chord is written lowest voice last and a long note can
   start before a short one that finishes later, so sizing off the tail cuts it.
2. An event with no pitch occupies its time without trying to render a 0 Hz
   tone. That is how a rest arrives from the reader.

Results: `ToneSequenceTests` 7/7. The regression guard, which is the whole
reason this is its own task: `ScalePitchTests` 8/8 (the YIN detector suite,
which would notice any change to what the notes actually sound like),
`ScalePlaybackTests` 2/2, `ScaleRenderTests` 5/5, `ToneRenderTests` 4/4,
`ToneEnvelopeTests` 3/3. 22/22 with behaviour unchanged.

- [x] **Step 5: Commit**

```sh
cd ios && xcodegen generate && cd ..
git add ios/Mellophone/Audio ios/MellophoneTests/ToneSequenceTests.swift ios/Mellophone.xcodeproj
git commit -m "refactor(audio): extract the buffer renderer so events can have real durations (#19)"
```

---

### Task 8: End-to-end against a real engraved PDF

The only task that needs a fixture file, and therefore the only one that needs
notation software installed.

**Files:**
- Create: `ios/MellophoneTests/Fixtures/one-octave-f-major.pdf`
- Create: `ios/MellophoneTests/ScoreImportEndToEndTests.swift`
- Modify: `ios/project.yml` if XcodeGen does not pick the fixture up automatically
- Modify: `.gitignore`

**Interfaces:**
- Consumes: every unit above.
- Produces: nothing new.

- [x] **Step 1: Author the fixture**

Install MuseScore Studio (free, `brew install --cask musescore`). Create a single
treble staff, key of F major (one flat), 4/4, and enter exactly this, one note
per beat:

```
measure 1: F4  G4  A4  Bb4
measure 2: C5  D5  E5  F5
measure 3: F5  E5  D5  C5
measure 4: Bb4 A4  G4  F4
```

Export to PDF as `ios/MellophoneTests/Fixtures/one-octave-f-major.pdf`.

**This content is ours.** Sam's charts are copyrighted arrangements, the repo is
public, and the app declares `DOES_NOT_USE_THIRD_PARTY_CONTENT`. His charts never
go in git. Add to `.gitignore`:

```
# Real charts are copyrighted third-party arrangements and the repo is public.
# Keep them local for manual spot checks only.
ios/MellophoneTests/Fixtures/local/
```

- [x] **Step 2: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import Mellophone

/// The one test that reads a real engraved PDF end to end. Everything else in
/// this suite works on hand-built geometry, which proves the logic but cannot
/// prove that a genuine MuseScore export parses at all.
///
/// The fixture is ours. Sam's charts are copyrighted and the repo is public.
final class ScoreImportEndToEndTests: XCTestCase {

    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "one-octave-f-major", withExtension: "pdf"))
    }

    func testReadsTheAuthoredScaleExactly() throws {
        let score = try XCTUnwrap(ScoreImporter.read(url: fixture()))
        XCTAssertEqual(score.keySignature, -1, "F major is one flat")
        XCTAssertEqual(score.timeSignature.beats, 4)
        XCTAssertEqual(score.timeSignature.unit, 4)
        XCTAssertEqual(score.voiceCount, 1)
        XCTAssertEqual(score.events.compactMap { $0.note?.name },
                       ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5",
                        "F5", "E5", "D5", "C5", "Bb4", "A4", "G4", "F4"])
        XCTAssertTrue(score.events.allSatisfy { $0.durationBeats == 1.0 })
    }

    /// Every measure sums, so nothing is suspect. If this fails, the reader is
    /// wrong somewhere and the validator is doing its job.
    func testNothingIsFlaggedOnAFileWeAuthored() throws {
        let score = try XCTUnwrap(ScoreImporter.read(url: fixture()))
        XCTAssertTrue(score.suspectMeasures.isEmpty,
                      "suspect: \(score.suspectMeasures.sorted())")
        XCTAssertTrue(score.unreadableSymbols.isEmpty,
                      "unreadable: \(score.unreadableSymbols.map { String($0, radix: 16) })")
    }

    /// A PDF with no music font must be refused plainly rather than producing a
    /// bad transcription. Two music PDFs on the build machine are vector
    /// flattened and would otherwise read as an empty score with no explanation.
    func testAPDFWithNoMusicFontIsRefused() throws {
        let plain = FileManager.default.temporaryDirectory.appendingPathComponent("plain.pdf")
        // Any PDF with no embedded music font. Draw one with Core Graphics.
        try makePlainPDF(at: plain)
        XCTAssertThrowsError(try ScoreImporter.readOrThrow(url: plain)) { error in
            XCTAssertEqual(error as? ImportError, .noReadableNotation)
        }
    }

    /// A one page PDF with text in a normal font and no music font anywhere.
    private func makePlainPDF(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.selectFont(name: "Helvetica", size: 14, encoding: .macRoman)
        ctx.setTextDrawingMode(.fill)
        ctx.showText(at: CGPoint(x: 20, y: 100), text: "not music")
        ctx.endPDFPage()
        ctx.closePDF()
    }
}
```

- [x] **Step 3: Write `ScoreImporter`**

```swift
import CoreGraphics
import Foundation

enum ImportError: Error, Equatable {
    case cannotOpenFile
    case noReadableNotation
    case noStaffFound
}

/// The one entry point the UI calls. Opens the document, picks the engraver
/// table from the fonts actually present, and runs every page through the
/// reader.
enum ScoreImporter {
    static func read(url: URL) -> Score? { try? readOrThrow(url: url) }

    static func readOrThrow(url: URL) throws -> Score {
        // OneDrive files are often not materialised locally, so a plain read
        // fails with "no such file". The security-scoped access plus a
        // coordinated read is what makes the File Provider fetch it.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let doc = CGPDFDocument(url as CFURL) else {
            Log.import_.error("[IMPORT] cannot open \(url.lastPathComponent, privacy: .public)")
            throw ImportError.cannotOpenFile
        }
        var pages: [PageGeometry] = []
        for i in 1...max(doc.numberOfPages, 1) {
            guard let page = doc.page(at: i) else { continue }
            pages.append(PDFGlyphReader.read(page: page))
        }
        let fontNames = Set(pages.flatMap { $0.glyphs.map(\.font) })
        guard let table = fontNames.compactMap({ MusicFontTable.forFont($0) }).first else {
            Log.import_.error("[IMPORT] no music font among \(fontNames.joined(separator: ", "), privacy: .public)")
            throw ImportError.noReadableNotation
        }
        let score = ScoreBuilder.build(pages: pages, font: table)
        // A music font with no staff under it means StaffFitter rejected every
        // candidate, which is a different failure from "not a score" and needs a
        // different message.
        guard !score.events.isEmpty else {
            Log.import_.error("[IMPORT] music font found but no staff systems fitted")
            throw ImportError.noStaffFound
        }
        return score
    }
}
```

Wrap the `CGPDFDocument` open in `NSFileCoordinator().coordinate(readingItemAt:)`
so a non-materialised OneDrive file is fetched rather than failing.

- [x] **Step 4: Run the test and verify it passes**

Run: `-only-testing:MellophoneTests/ScoreImportEndToEndTests`
Expected: PASS, 3 tests.

If the fixture is not found in the bundle, XcodeGen did not sweep it into the
resources phase. Add an explicit `resources` entry for
`MellophoneTests/Fixtures` under the `MellophoneTests` target in `project.yml`
and regenerate. Do not hand-edit the pbxproj.

- [x] **Step 5: Spot check against the real charts, by hand**

Copy `PEAK mello.pdf` and the Florida chart into
`ios/MellophoneTests/Fixtures/local/` (gitignored) and run the importer against
both from a scratch test, printing the score. Compare to the spike output
recorded in issue #19. Note in an issue comment how many measures came back
suspect, which is the honest measure of where phase 2 actually landed.

**Corrected during execution.**

1. **The MusicXML source is committed next to the PDF.** The plan committed only
   the exported binary. A fixture nobody can open or regenerate is a fixture
   nobody can check, and the point of a self-authored fixture is that the ground
   truth is known exactly. `one-octave-f-major.musicxml` carries the regeneration
   command in a comment at its head.
2. **`Fixtures/local/` is excluded in `project.yml`, not just `.gitignore`.**
   Gitignore stops the real charts being committed. It does NOT stop XcodeGen
   sweeping them into the test bundle's resources, which would put copyrighted
   arrangements into a build product: the same mistake as committing them, one
   step further down the pipeline. Verified with Sam's actual charts sitting in
   that directory: zero references in the generated pbxproj.
3. **A fourth test.** A file that is not a PDF at all must fail as
   `cannotOpenFile` and not as `noReadableNotation`, because those are different
   sentences to the user and send someone to different next steps. The plan had
   three tests; this is the fourth.
4. The plan's `Log.import_` does not exist. The logger is `Log.score`, as Task 3
   already recorded.

**The fixture, read end to end through `ScoreImporter`:**

```
fonts: ["Edwin-Roman", "Leland"]
page 1: 1 system, 47 glyphs, 42 paths
key -1  time 4/4  voices 1
names     F4 G4 A4 Bb4 C5 D5 E5 F5 F5 E5 D5 C5 Bb4 A4 G4 F4
durations all 1.0
measures  1111 2222 3333 4444
suspect []  unreadable []
```

Every pitch, every duration and every measure number is what was authored, and
the validator flags nothing. Rendered and checked by eye as well, because a
number agreeing with a number I typed is weaker evidence than a picture.

- [x] **Step 6: Commit and close out**

```sh
cd ios && xcodegen generate && cd ..
git add ios/MellophoneTests ios/Mellophone/Import/ScoreImporter.swift ios/project.yml .gitignore ios/Mellophone.xcodeproj
git commit -m "feat(import): end to end read of an engraved PDF, with a self-authored fixture (#19)"
```

Then update `ios/README.md` with a section on the import pipeline and the
engraver tables, and comment on #19 with files, results, divergences and
follow-ups, including `[tokens: XXXk]`.

---

## What this plan does not build

Phase 3 (the `.fileImporter` UI, the staff view with fingerings, the voice
picker, loop and tempo) and phase 4 (the web version) are separate plans. At the
end of this plan the reader works and is proven, and nothing in the app calls it
yet.

**Phase 3 was then built without a plan of its own**, straight from the design,
on 2026-10-09. What shipped and where it departs from the design is recorded in
the design's Phases section and in `ios/README.md` under "Charts play a few bars
at a time". The two things below that this plan deferred to it both landed
there: chunked rendering is `PartTimeline.chunks` and `PartPlayer`, and the
screen says in words that repeats are not followed.

Chunked buffer rendering for long parts is specified but belongs with playback,
so it lands in phase 3 alongside the transport that needs it. `ToneSequence`
renders one buffer here, which is correct for the fixture-sized scores this plan
tests.

Repeats, first and second endings, D.S. and coda are not handled. Playback order
is the page as written, top to bottom. That has to be said in the UI when phase 3
lands.

**What this plan got wrong about tempo (#41, 2026-10-18).** It treated the
tempo as a phase 3 control, a number the student sets, and the reader dropping
the tempo mark as a feature of the text-font exclusion. A director prints the
tempo and a part changes it: PEAK prints twelve. The mark is read now, off the
whole page rather than a staff's glyphs (`Import/TempoMarks.swift`), and the
student's number is a share of the page's. See `ios/README.md`, "The page's
tempo".
