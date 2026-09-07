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

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import Mellophone

/// Real numbers: the MuseScore chart in issue #19 puts its five lines at
/// 360.50, 365.46, 370.42, 375.38 and 380.34, a spacing of 4.96 that is even to
/// within rounding. Those are the values used here.
final class StaffFitterTests: XCTestCase {

    private func rule(y: Double, x0: Double = 50, x1: Double = 500, h: Double = 0.7) -> PlacedPath {
        let r = CGRect(x: x0, y: y, width: x1 - x0, height: h)
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

    /// Four lines is not a staff, and neither is six evenly spaced ones with a
    /// gap in the middle. Refusing both is what keeps text underlines and
    /// bracket lines out of the result.
    func testRejectsGroupsThatAreNotFiveEvenLines() {
        XCTAssertTrue(StaffFitter.systems(in: [360.5, 365.46, 370.42, 375.38].map { rule(y: $0) }).isEmpty)
        let uneven = [360.5, 365.46, 370.42, 379.0, 384.0].map { rule(y: $0) }
        XCTAssertTrue(StaffFitter.systems(in: uneven).isEmpty)
    }

    /// A beam is a filled path too, and it is short and thick. A slur is tall
    /// and curved. Neither may be mistaken for a staff line.
    /// Sibelius strokes staff lines, MuseScore fills them, and a stroked line
    /// has bounds of zero height. Both must be found.
    func testFindsStrokedStaffLinesAsWellAsFilled() {
        let stroked = [360.50, 365.46, 370.42, 375.38, 380.34].map {
            PlacedPath(vertices: [CGPoint(x: 50, y: $0), CGPoint(x: 500, y: $0)],
                       filled: false,
                       bounds: CGRect(x: 50, y: $0, width: 450, height: 0))
        }
        XCTAssertEqual(StaffFitter.systems(in: stroked).count, 1,
                       "a stroked staff is still a staff")
    }

    func testIgnoresShortAndThickPaths() {
        var paths = [360.50, 365.46, 370.42, 375.38, 380.34].map { rule(y: $0) }
        paths.append(rule(y: 362.0, x0: 100, x1: 118, h: 3.5))   // a beam
        let systems = StaffFitter.systems(in: paths)
        XCTAssertEqual(systems.count, 1)
        XCTAssertEqual(systems[0].lineYs.count, 5)
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Expected: compile failure, `cannot find 'StaffFitter' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import CoreGraphics
import Foundation

/// Where the staves are on a page. Pure geometry: this file contains no musical
/// vocabulary at all, which is what keeps it testable with made-up rectangles.
struct StaffSystem {
    let lineYs: [Double]
    let xRange: ClosedRange<Double>

    var topLineY: Double { lineYs[0] }
    /// Half the gap between adjacent lines, which is one diatonic step and the
    /// unit every pitch calculation is expressed in.
    var halfSpace: Double { (lineYs[4] - lineYs[0]) / 8 }
}

enum StaffFitter {
    /// A staff line is long, thin and horizontal. These thresholds are in PDF
    /// points and were measured against the charts in issue #19, where lines run
    /// several hundred points wide (517.1 in PEAK mello.pdf) and no more than one
    /// point thick, while beams are under twenty wide and over three thick.
    private static let minimumWidth: Double = 40
    /// Admits 0, because a stroked line's bounds have no height at all.
    private static let maximumThickness: Double = 2.0
    /// Spacing across the five lines of one staff must agree to this, in points.
    /// The observed variation in a real export is under 0.05.
    private static let spacingTolerance: Double = 0.4

    static func systems(in paths: [PlacedPath]) -> [StaffSystem] {
        // Deliberately NOT filtering on `filled`. Sibelius strokes its staff
        // lines and MuseScore fills them; requiring a fill finds 6 candidates on
        // a PEAK mello.pdf page that has 50.
        let rules = paths
            .filter { $0.bounds.width >= minimumWidth
                && $0.bounds.height <= maximumThickness }
            .sorted { $0.bounds.midY < $1.bounds.midY }

        var systems: [StaffSystem] = []
        var i = 0
        while i + 4 < rules.count {
            let window = Array(rules[i..<(i + 5)])
            let ys = window.map { Double($0.bounds.midY) }
            let gaps = zip(ys, ys.dropFirst()).map { $1 - $0 }
            let even = (gaps.max()! - gaps.min()!) < spacingTolerance
            if even, gaps[0] > 1, gaps[0] < 30 {
                let x0 = window.map { Double($0.bounds.minX) }.min()!
                let x1 = window.map { Double($0.bounds.maxX) }.max()!
                systems.append(StaffSystem(lineYs: ys, xRange: x0...x1))
                i += 5
            } else {
                i += 1
            }
        }
        Log.import_.info("[IMPORT] fitted \(systems.count, privacy: .public) staff systems")
        return systems
    }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```sh
cd ios && xcodegen generate && cd ..
git add ios/Mellophone/Import/StaffFitter.swift ios/MellophoneTests/StaffFitterTests.swift ios/Mellophone.xcodeproj
git commit -m "feat(import): group horizontal rules into five-line staff systems (#19)"
```

---

### Task 4: `Score` model and `ScoreBuilder` pitch

**Files:**
- Create: `ios/Mellophone/Import/Score.swift`
- Create: `ios/Mellophone/Import/ScoreBuilder.swift`
- Test: `ios/MellophoneTests/ScoreBuilderPitchTests.swift`

**Interfaces:**
- Consumes: `PageGeometry`, `StaffSystem`, `MusicFontTable`, and `Note` from
  `ios/Mellophone/Model/Note.swift`.
- Produces: `struct ScoreEvent`, `struct Score`,
  `enum ScoreBuilder { static func build(pages: [PageGeometry], font: MusicFontTable) -> Score }`,
  and internally `static func pitch(staffStep: Int, keySignature: Int, accidental: Accidental?) -> String`.

- [ ] **Step 1: Write the failing test**

Tests build `PageGeometry` by hand, so this task is independent of Tasks 2 and 3
and can be worked on in parallel with them.

```swift
import XCTest
import CoreGraphics
@testable import Mellophone

/// Pitch reading, tested against hand-built geometry rather than a PDF, so the
/// staff coordinates are exact and the failure messages point at the music
/// logic rather than at the parser.
///
/// Treble clef, top line F5, and one half-space per diatonic step. The line and
/// space values are the same ones StaffGeometryTests pins for the drawing side.
final class ScoreBuilderPitchTests: XCTestCase {

    private let lineYs = [360.50, 365.46, 370.42, 375.38, 380.34]
    private var system: StaffSystem { StaffSystem(lineYs: lineYs, xRange: 50...500) }

    private func head(x: Double, y: Double, scalar: UInt32 = 0xE0A4) -> PlacedGlyph {
        PlacedGlyph(scalar: scalar, x: x, y: y, size: 10, font: "Leland")
    }
    private func clef() -> PlacedGlyph {
        PlacedGlyph(scalar: 0xE050, x: 55, y: 375.38, size: 10, font: "Leland")
    }

    func testNotesOnLinesReadAsFDBGE() throws {
        let heads = zip([100.0, 120, 140, 160, 180], lineYs).map { head(x: $0, y: $1) }
        let score = ScoreBuilder.build(
            pages: [PageGeometry(glyphs: [clef()] + heads, paths: staffPaths())],
            font: try XCTUnwrap(MusicFontTable.forFont("Leland")))
        XCTAssertEqual(score.events.compactMap { $0.note?.name }, ["F5", "D5", "B4", "G4", "E4"])
    }

    func testNotesOnSpacesReadAsECAF() throws {
        let spaceYs = [363.0, 367.94, 372.90, 377.86]
        let heads = zip([100.0, 120, 140, 160], spaceYs).map { head(x: $0, y: $1) }
        let score = ScoreBuilder.build(
            pages: [PageGeometry(glyphs: [clef()] + heads, paths: staffPaths())],
            font: try XCTUnwrap(MusicFontTable.forFont("Leland")))
        XCTAssertEqual(score.events.compactMap { $0.note?.name }, ["E5", "C5", "A4", "F4"])
    }

    /// One flat in the key signature makes every B a Bb, including the B in a
    /// different octave, which is the case a naive implementation gets wrong.
    func testKeySignatureAppliesToEveryOctave() throws {
        let keyFlat = PlacedGlyph(scalar: 0xE260, x: 70, y: 370.42, size: 10, font: "Leland")
        let heads = [head(x: 100, y: 370.42), head(x: 120, y: 350.58)]  // B4 and B5
        let score = ScoreBuilder.build(
            pages: [PageGeometry(glyphs: [clef(), keyFlat] + heads, paths: staffPaths())],
            font: try XCTUnwrap(MusicFontTable.forFont("Leland")))
        XCTAssertEqual(score.events.compactMap { $0.note?.name }, ["Bb4", "Bb5"])
    }

    /// An inline accidental holds for the rest of its measure and then stops.
    func testInlineAccidentalPersistsToTheBarlineAndNoFurther() throws {
        let sharp = PlacedGlyph(scalar: 0xE262, x: 95, y: 375.38, size: 10, font: "Leland")
        let barline = PlacedPath(vertices: [], filled: true,
                                 bounds: CGRect(x: 150, y: 360.5, width: 0.8, height: 19.84))
        let heads = [head(x: 100, y: 375.38), head(x: 120, y: 375.38), head(x: 170, y: 375.38)]
        let score = ScoreBuilder.build(
            pages: [PageGeometry(glyphs: [clef(), sharp] + heads, paths: staffPaths() + [barline])],
            font: try XCTUnwrap(MusicFontTable.forFont("Leland")))
        XCTAssertEqual(score.events.compactMap { $0.note?.name }, ["G#4", "G#4", "G4"])
    }

    /// Two noteheads at the same x are one chord, and on a horn part that is
    /// divisi. The Florida chart in issue #19 is written this way throughout.
    func testStackedNoteheadsBecomeTwoVoices() throws {
        let heads = [head(x: 100, y: 365.46), head(x: 100, y: 370.42)]
        let score = ScoreBuilder.build(
            pages: [PageGeometry(glyphs: [clef()] + heads, paths: staffPaths())],
            font: try XCTUnwrap(MusicFontTable.forFont("Leland")))
        XCTAssertEqual(score.voiceCount, 2)
        XCTAssertEqual(score.events.filter { $0.voice == 0 }.compactMap { $0.note?.name }, ["D5"])
        XCTAssertEqual(score.events.filter { $0.voice == 1 }.compactMap { $0.note?.name }, ["B4"])
    }

    /// A pitch above C6 is outside the instrument's range, so Note.named
    /// returns nil. It must NOT collapse into a rest: an event that keeps its
    /// duration and reports its name is honest, silence is not.
    func testOutOfRangeNoteIsKeptAndNamedRatherThanSilenced() throws {
        // Four half-spaces above the top line is B6, well past C6.
        let tooHigh = head(x: 100, y: lineYs[0] - 8 * 2.48)
        let score = ScoreBuilder.build(
            pages: [PageGeometry(glyphs: [clef(), tooHigh], paths: staffPaths())],
            font: try XCTUnwrap(MusicFontTable.forFont("Leland")))
        XCTAssertEqual(score.events.count, 1)
        XCTAssertNil(score.events[0].note)
        XCTAssertFalse(score.events[0].isRest, "an out of range note is not a rest")
        XCTAssertEqual(score.events[0].outOfRangeName, "B6")
    }

    private func staffPaths() -> [PlacedPath] {
        lineYs.map {
            PlacedPath(vertices: [], filled: true,
                       bounds: CGRect(x: 50, y: $0, width: 450, height: 0.7))
        }
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Expected: compile failure, `cannot find 'ScoreBuilder' in scope`.

- [ ] **Step 3: Write `Score.swift`**

```swift
import Foundation

/// One sounding event, or a rest.
///
/// `note` is the app's existing Note, not a new pitch type, so an imported part
/// gets fingeringFor, staffPosition and frequency for free and renders on the
/// same staff as the trainer and the drill.
struct ScoreEvent: Identifiable {
    let id = UUID()
    let note: Note?
    /// Set when the page asked for a pitch outside F#3 to C6, which Note.named
    /// cannot return. Without this a note above the horn's range would come back
    /// as note == nil and be played as SILENCE, which is the worst possible
    /// failure: the part would sound right apart from the bars Sam most needs to
    /// hear. The event keeps its duration and the UI shows the name greyed.
    let outOfRangeName: String?
    /// Beats from the start of the score, not from the start of the measure.
    let onsetBeats: Double
    let durationBeats: Double
    let measure: Int
    let voice: Int

    var isRest: Bool { note == nil && outOfRangeName == nil }
}

struct Score {
    let events: [ScoreEvent]
    let timeSignature: (beats: Int, unit: Int)
    /// Negative for flats, positive for sharps, zero for C.
    let keySignature: Int
    let voiceCount: Int
    /// Measures whose durations did not sum to the time signature. These render
    /// flagged and tappable rather than being silently played wrong.
    let suspectMeasures: Set<Int>
    /// Codepoints the font table did not recognise, so a chart that defeats the
    /// reader can say which glyphs did it.
    let unreadableSymbols: [UInt32]

    static let empty = Score(events: [], timeSignature: (4, 4), keySignature: 0,
                             voiceCount: 0, suspectMeasures: [], unreadableSymbols: [])
}
```

- [ ] **Step 4: Write the pitch half of `ScoreBuilder.swift`**

Implement in these stages, each with the test above as the gate:

1. Refit systems from the page's paths with `StaffFitter`, and assign each glyph
   to the system whose band, widened by six half-spaces on each side for ledger
   lines, contains its y.
2. Read the head of each system: the first `gClef` or `fClef` glyph, then the run
   of `sharp` or `flat` glyphs whose x is within roughly eight half-spaces of the
   clef, which is the key signature. Its count is `keySignature`, signed. Then
   the `timeSigDigit` glyphs, paired top and bottom by y.

   **Accept a `timeSigDigit` only when it is inside the staff, within the head
   region of the system, and shares its x with no notehead.** The same digit
   glyphs are used for measure numbers and tuplet numbers, which in
   `PEAK mello.pdf` outnumber the real time signatures 35 to 8 and sit below the
   staff on a notehead's x. Reading one of those as a time signature makes every
   measure fail the sum check, which turns the validator from signal into noise.
   Default to 4/4 when no digit pair qualifies, and log `[IMPORT]` when you do.
3. Any remaining accidental is inline. Attach it to the nearest notehead to its
   right within two half-spaces of the same y, and record it in a
   `[letter: Accidental]` table that is cleared at every barline.
4. Group noteheads by x, rounded to a tenth of a point. Sort each group by y
   ascending, which is highest pitch first, and that index is the voice.
   `voiceCount` is the largest group size.
5. Convert y to a diatonic step with `round((y - topLineY) / halfSpace)`, where 0
   is the clef's top-line pitch. Apply the key signature by letter, then any
   inline accidental, which wins. Look the resulting name up with `Note.named`.
   When it returns nil the pitch is outside F#3 to C6: build the event with
   `note: nil` and `outOfRangeName` set to the computed name. Never drop it and
   never let it fall through as a rest.

Note the coordinate direction. `StaffGeometry` in this app draws with y
increasing downward, and PDF page space has y increasing upward. Whichever
direction `PDFGlyphReader` reports, `ScoreBuilder` must normalise so that a
larger step index is a lower pitch, and there must be a test asserting F5 is the
top line, which the first test above is.

- [ ] **Step 5: Run the test and verify it passes**

Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```sh
cd ios && xcodegen generate && cd ..
git add ios/Mellophone/Import ios/MellophoneTests/ScoreBuilderPitchTests.swift ios/Mellophone.xcodeproj
git commit -m "feat(import): read pitch, key signature and inline accidentals off a staff (#19)"
```

---

### Task 5: `ScoreBuilder` rhythm

**Files:**
- Modify: `ios/Mellophone/Import/ScoreBuilder.swift`
- Test: `ios/MellophoneTests/ScoreBuilderRhythmTests.swift`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: no new public types. `ScoreEvent.durationBeats` becomes correct.

- [ ] **Step 1: Write the failing test**

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

- [ ] **Step 2: Run the test and verify it fails**

Expected: FAIL. Durations are all 1.0 because Task 4 leaves them at the
notehead's implied value.

- [ ] **Step 3: Implement the rhythm stages**

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

- [ ] **Step 4: Run the test and verify it passes**

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Write the failing test**

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

- [ ] **Step 2: Run the test and verify it fails**

Expected: FAIL on `testShortMeasureIsFlagged`, since `suspectMeasures` is still
always empty.

- [ ] **Step 3: Implement**

Split events at barlines into measures, sum `durationBeats` per measure per
voice, and compare to `beats` from the time signature. Insert the measure index
into `suspectMeasures` when any voice disagrees by more than 0.001. Do not drop
or repair the events; the UI shows them flagged. Log each flagged measure with
`[IMPORT]` and its computed sum, because that number is what tells you which
stage got it wrong.

Two measures are exempt from the check and must not be flagged: the first, when
it is shorter than the time signature, which is a pickup, and the last, for the
same reason.

- [ ] **Step 4: Run the test and verify it passes**

Expected: PASS, 5 tests.

- [ ] **Step 5: Run the WHOLE suite**

```sh
cd ios && xcodebuild -project Mellophone.xcodeproj -scheme Mellophone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData test
```

Expected: all pre-existing tests still pass. `BeatScheduleTests`,
`ScalePitchTests` and `FingeringChartTests` in particular must be untouched.

- [ ] **Step 6: Commit**

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

- [ ] **Step 1: Write the failing test**

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

- [ ] **Step 2: Run the test and verify it fails**

Expected: compile failure, `cannot find 'ToneSequence' in scope`.

- [ ] **Step 3: Move the renderer**

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

- [ ] **Step 4: Run BOTH suites and verify they pass**

```sh
-only-testing:MellophoneTests/ToneSequenceTests -only-testing:MellophoneTests/ScalePlayerTests -only-testing:MellophoneTests/ScalePitchTests
```

Expected: PASS. `ScalePitchTests` measures the fundamental of every rendered note
with a YIN detector, so it is the real proof the move changed no sound.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Author the fixture**

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

- [ ] **Step 2: Write the failing test**

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

- [ ] **Step 3: Write `ScoreImporter`**

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

- [ ] **Step 4: Run the test and verify it passes**

Run: `-only-testing:MellophoneTests/ScoreImportEndToEndTests`
Expected: PASS, 3 tests.

If the fixture is not found in the bundle, XcodeGen did not sweep it into the
resources phase. Add an explicit `resources` entry for
`MellophoneTests/Fixtures` under the `MellophoneTests` target in `project.yml`
and regenerate. Do not hand-edit the pbxproj.

- [ ] **Step 5: Spot check against the real charts, by hand**

Copy `PEAK mello.pdf` and the Florida chart into
`ios/MellophoneTests/Fixtures/local/` (gitignored) and run the importer against
both from a scratch test, printing the score. Compare to the spike output
recorded in issue #19. Note in an issue comment how many measures came back
suspect, which is the honest measure of where phase 2 actually landed.

- [ ] **Step 6: Commit and close out**

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

Chunked buffer rendering for long parts is specified but belongs with playback,
so it lands in phase 3 alongside the transport that needs it. `ToneSequence`
renders one buffer here, which is correct for the fixture-sized scores this plan
tests.

Repeats, first and second endings, D.S. and coda are not handled. Playback order
is the page as written, top to bottom. That has to be said in the UI when phase 3
lands.
