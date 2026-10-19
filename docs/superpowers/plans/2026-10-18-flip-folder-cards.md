# Flip Folder Card View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a chart as the director's own page, four lines to a sideways card, with the playing note boxed, and print the part as lyre cards for an 18.0 x 13.6 cm flip folder sleeve.

**Architecture:** The reader keeps where every note, line and bar was printed (`NotePlace`, `SystemPlace`). Pure layers turn that into cards (`LyreCards`), view geometry (`CardGeometry`) and print layout (`LyreCardPrint`). One SwiftUI screen draws strips of the PDF with `CGPDFPage`, boxes the notes the player reports through `PartModel.eventIDs(inSlot:)`, and rotates this screen alone to landscape.

**Tech Stack:** Swift, SwiftUI, CoreGraphics PDF, XCTest, XcodeGen. iOS 17, iPhone only.

**Spec:** `docs/superpowers/specs/2026-10-18-flip-folder-card-view-design.md` (issue #43, branch `feat/flip-folder-cards`)

## Global Constraints

- Nothing over the network. Printing is the iOS share sheet only.
- Sam's charts never in git, never in a build, never in a committed test output. Local tests skip without `ios/MellophoneTests/Fixtures/local/`.
- `ios/project.yml` is the source of truth; run `cd ios && xcodegen generate` after adding files.
- One `PartPlayer` (owned by the charts card); the box reads `player.currentSlot`, never its own clock.
- Microphone only through `NoteCheckView` (existing purpose).
- Suspect bars shown and played, never hidden.
- Fingering only via `Fingering.value(for:on:)` for the selected instrument.
- Logging prefix `[CARD]` on success and failure paths via `Log.score`; debug builds also `FileLog.write`.
- No em or en dashes in code comments, docs, commits.
- XCTest, iPhone 17 simulator `F261A484-12AC-4611-9344-348D0EB38138`, `bash ios/scripts/quiet-simulator.sh` before every test run or launch, never two `xcodebuild` at once.
- Card view: 4 lines per card default, 3 or 2 allowed (`mello-card-lines`); Music default (`mello-part-view`, `music` or `names`).
- Print card 17.8 x 13.4 cm; top 2.2 cm clear; 0.4 cm clear on other edges; music width 17.0 cm; Letter or A4 two up with cut lines, or one card per page.

## Review Focus

1. **A title or header above the first line of page 1** must not be pulled into that line's strip. Ink bounds are clamped (Task 1 test on the sample chart, whose title sits above line 1).
2. **A note the reader could not place** gets no box and no tap target, and logs once per range (Task 4 test with a nil `place`).
3. **Leaving the card view any way** (Done, Names, the instrument chip, closing the chart) returns the app to portrait (Task 5 manual check, listed in its verification step).
4. **A chart with fewer lines than one card** shows one card and no dots; a final partial card is still a card (Task 3 test on the traps fixture, 2 lines).
5. **The note check opened from a sideways card** still fits: `NoteCheckView`'s `ViewThatFits` must reach its scrolling form at 402 points tall (Task 5 simulator screenshot with `-checkNote`).

---

### Task 1: The reader keeps where things were printed

**Files:**
- Modify: `ios/Mellophone/Import/Score.swift`
- Modify: `ios/Mellophone/Import/ScoreBuilder.swift` (build loop near line 188; event creation near 656, 671, 743)
- Test: `ios/MellophoneTests/PlacementTests.swift` (new)

**Interfaces:**
- Produces, in `Score.swift`:
  - `struct NotePlace: Equatable { let system: Int; let x: Double; let y: Double }`: index into `Score.systems`; the glyph origin in PDF user space (y up).
  - `struct BarSpan: Equatable { let measure: Int; let x0: Double; let x1: Double }`
  - `struct SystemPlace: Equatable { let page: Int; let lineYs: [Double]; let xRange: ClosedRange<Double>; let halfSpace: Double; let inkTop: Double; let inkBottom: Double; let bars: [BarSpan] }` with `var topLineY: Double { lineYs.last! }`, `var bottomLineY: Double { lineYs.first! }`, `var firstMeasure: Int?`, `var lastMeasure: Int?`.
  - `ScoreEvent.place: NotePlace?` (var, default nil). `Score.systems: [SystemPlace]` (init param default `[]`).

- [ ] **Step 1: Write the failing tests** in `PlacementTests.swift`:
  - `testEveryPitchedEventOfTheTrapsFixtureIsPlacedOnItsSystem`: read `Fixtures/reader-traps.pdf`; `score.systems.count == 2`; every event with `!isRest` has `place != nil`; for each, `score.systems[place.system]` has `abs(place.y - bottomLineY) <= 12 * halfSpace` and `xRange.contains(place.x)`.
  - `testBarsCoverEveryMeasureOnceInOrder`: traps fixture; `score.systems.flatMap(\.bars).map(\.measure) == Array(1...9)`; every span has `x0 < x1`.
  - `testInkBoundsHoldTheTempoMarkButNotTheTitle`: traps fixture system 0 `inkTop >= topLineY + 8 * halfSpace` (the "♩ = 96" sits about 12 hs up) and `inkTop <= topLineY + 14 * halfSpace`; sample chart (`SampleChart.url`) system 0 `inkTop <= topLineY + 14 * halfSpace` (its title is higher).
  - `testPEAKPlacesEveryPitchedNote` (local, `XCTSkip` without the file): every pitched event placed; `systems.count >= 9`; the first nine `bottomLineY` values on page 0 match 595.67, 531.19, 466.70, 402.08, 337.59, 272.24, 207.76, 143.13, 78.65 within 0.05.
- [ ] **Step 2: Run** `xcodebuild test ... -only-testing:MellophoneTests/PlacementTests`. Expected: compile failure (no `place`, no `systems`).
- [ ] **Step 3: Implement.** In the build loop keep a running system index across pages. Set `place` on every event made from a glyph (note heads and rest glyphs). Build `bars` from the `barlines` the loop already computes and the `measure` counter as it advances (a bar runs from the previous barline, or the first note's x minus 2 hs, to the barline that closes it; trailing bars close at `xRange.upperBound`). Ink: take every page glyph (ALL fonts, text included) and every page path whose vertical middle is nearer this system's middle than any other system's and whose x overlaps `xRange`; `inkTop = min(max of their tops, topLineY + 14 * hs)`, `inkBottom = max(min of their bottoms, bottomLineY - 10 * hs)`, and never inside the staff. Log `[CARD] system N page P: bars a to b, ink +t/-b hs` at info; log at error any pitched event left without a place.
- [ ] **Step 4: Run** the same tests. Expected: PASS. Then run `ChartReaderTrapsTests`, `SampleChartTests`, `ScoreImportEndToEndTests` (notes must read identically). Expected: PASS.
- [ ] **Step 5: Measure on PEAK** in the scratch harness (copy the changed Import files; add a `DUMP_PLACES` mode printing each system's bars and ink): every system's first bar equals the bar number printed at the start of that line (1, 11, 20, 27, 36, 42, 49, 54, 65 on page 1).
- [ ] **Step 6: Commit** `feat(import): keep where every note, line and bar was printed (#43)`.

### Task 2: A two page fixture of our own

**Files:**
- Create: `ios/MellophoneTests/Fixtures/card-turns.musicxml`, `ios/MellophoneTests/Fixtures/card-turns.pdf`
- Modify: `ios/project.yml` only if fixtures are listed explicitly (check how `reader-traps.pdf` is included)
- Test: `ios/MellophoneTests/PlacementTests.swift`

**Interfaces:** Produces the fixture later tasks read: 2 pages, 7 systems (4 on page 1, 3 on page 2), 4/4, one flat, 21 bars of plain quarters and halves in F major, bars numbered 1 to 21, `<print new-system="yes"/>` every 3 bars and `<print new-page="yes"/>` at bar 13. Self authored, with the regenerate command in its header comment like `reader-traps.musicxml`.

- [ ] **Step 1: Write the failing test** `testCardTurnsFixtureHasSevenLinesOverTwoPages`: `systems.count == 7`; `systems.map(\.page) == [0,0,0,0,1,1,1]`; `systems.map(\.firstMeasure) == [1,4,7,10,13,16,19]`; every pitched event placed.
- [ ] **Step 2: Run it.** Expected: FAIL (file missing).
- [ ] **Step 3: Write the MusicXML and engrave** with `"/Applications/MuseScore 4.app/Contents/MacOS/mscore" -o card-turns.pdf card-turns.musicxml`. Render both pages with the harness `render` and look at them.
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Commit** `test(import): a two page chart of our own for card turns (#43)`.

### Task 3: Cards and printed cards, as arithmetic

**Files:**
- Create: `ios/Mellophone/Model/LyreCards.swift`
- Test: `ios/MellophoneTests/LyreCardsTests.swift`

**Interfaces:**
- Consumes: `SystemPlace` (Task 1).
- Produces:
  - `struct LyreCard: Equatable { let index: Int; let systems: Range<Int>; let firstMeasure: Int; let lastMeasure: Int }`
  - `enum LyreCards { static func cards(_ systems: [SystemPlace], linesPerCard: Int) -> [LyreCard]; static func index(holding measure: Int, in cards: [LyreCard]) -> Int? }` (`linesPerCard` clamped to 2...4).
  - `enum LyreCardPrint` with `static let cardSize = CGSize(width: 504.57, height: 379.84)` (17.8 x 13.4 cm), `static let ringStrip: CGFloat = 62.36` (2.2 cm), `static let edge: CGFloat = 11.34` (0.4 cm), `static let musicWidth: CGFloat = 481.89` (17.0 cm), `static func layout(_ systems: [SystemPlace]) -> (scale: CGFloat, cards: [Range<Int>])`.
  - `static func strip(_ system: SystemPlace) -> CGRect`: the PDF rect a line is cut from, `x: xRange.lowerBound - 2 hs ... xRange.upperBound + 1 hs`, `y: inkBottom - 1 hs ... inkTop + 1 hs`. Lives on `LyreCards`; both the screen and the print use it.

- [ ] **Step 1: Write the failing tests:**
  - `testFourLinesToACardAcrossAPageBreak`: card-turns fixture, 4 lines: two cards, `systems == 0..<4` and `4..<7`, measures 1...12 and 13...21.
  - `testTwoLinesToACard`: same fixture, 2 lines: four cards, the last `6..<7`.
  - `testFewerLinesThanACardIsOneCard`: traps fixture, 4 lines: one card `0..<2`.
  - `testCardHoldingAMeasure`: card-turns, 4 lines: `index(holding: 12) == 0`, `index(holding: 13) == 1`, `index(holding: 99) == nil`.
  - `testPrintedCardsKeepEveryLineOnceAndFitTheCard`: card-turns: `cards.flatMap { Array($0) } == Array(0..<7)`; for every card, the sum of `strip(_:).height * scale` over its lines is `<= cardSize.height - ringStrip - edge`; the widest `strip.width * scale` equals `musicWidth` within 0.5.
  - `testPEAKCardsStartAtThePrintedBars` (local): 4 lines, card 0 starts at bar 1, card 1 at bar 36, card 2 at bar 65; `index(holding: 34) == 0`.
- [ ] **Step 2: Run.** Expected: compile failure.
- [ ] **Step 3: Implement.** Print packing is greedy in reading order at the one fixed scale (`musicWidth / widest strip width`), never splitting a line.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(cards): lay a chart out as lyre cards (#43)`.

### Task 4: Geometry on a card

**Files:**
- Create: `ios/Mellophone/Model/CardGeometry.swift`
- Test: `ios/MellophoneTests/CardGeometryTests.swift`

**Interfaces:**
- Consumes: `NotePlace`, `SystemPlace`, `LyreCards.strip(_:)`.
- Produces `struct CardGeometry` built from `(systems: [SystemPlace], card: LyreCard, width: CGFloat)`:
  - `let scale: CGFloat` (view points per PDF point, so the widest strip fills `width`), `let height: CGFloat`, `func stripFrame(_ system: Int) -> CGRect` (stacked top to bottom, no gaps).
  - `func point(x: Double, y: Double, system: Int) -> CGPoint` (PDF y up to view y down).
  - `func box(_ place: NotePlace) -> CGRect`: centred on `(x + 1.2 hs, y)`, `3.5 hs` wide, `2.6 hs` tall, in view points.
  - `func note(at point: CGPoint, among events: [ScoreEvent]) -> ScoreEvent?`: nearest placed pitched event on the strip under the point, centre within `2.5 hs`; nil otherwise.
  - `func measure(at point: CGPoint) -> Int?`: the `BarSpan` under the point on the strip under it.

- [ ] **Step 1: Write the failing tests** on the card-turns fixture at `width: 750`:
  - `testStripsStackWithNoGap`: `stripFrame(1).minY == stripFrame(0).maxY`; `height == stripFrame(3).maxY`.
  - `testABoxSitsOnItsNotehead`: for every placed event on card 0, `box(place).contains(point(x: place.x + 1.2 * hs, y: place.y, system: place.system))`, and the box lies inside its strip frame.
  - `testTappingANoteFindsIt`: tapping each box's centre returns that event; a point midway between two notes more than 6 hs apart returns nil.
  - `testUnplacedNotesAreNotTargets`: an event copied with `place = nil` is never returned.
  - `testTappingABarFindsItsMeasure`: the midpoint of every `BarSpan` on card 0 at the strip's middle returns that measure.
- [ ] **Step 2: Run.** Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(cards): where a note and a bar sit on a card (#43)`.

### Task 5: The card screen

**Files:**
- Create: `ios/Mellophone/Views/CardView.swift`, `ios/Mellophone/Views/CardStrips.swift` (renders and caches strip images from the chart's `CGPDFDocument` at screen scale), `ios/Mellophone/App/OrientationLock.swift`
- Modify: `ios/Mellophone/Views/PartView.swift` (Music / Names switch; `ready` shows `CardView` for Music), `ios/Mellophone/Model/Preferences.swift` (`partView`, `cardLines`), `ios/Mellophone/App/MellophoneApp.swift` (`@UIApplicationDelegateAdaptor`), `ios/project.yml` (iPhone orientations: portrait, landscape left, landscape right)
- Test: `ios/MellophoneTests/PartModelTests.swift` (prefs defaults), simulator screenshots

**Interfaces:**
- Consumes: Tasks 1, 3, 4; `PartModel.eventIDs(inSlot:)`, `entry(inSlot:)`, `pick(_:)`, `start(at:)`, `end(at:)`, `loop`; `PartView.hear(_:)` and `check(_:)` (pass them in as closures).
- Produces: `enum PartViewMode: String { case music, names }`; `Preferences.partView` (`mello-part-view`, default `.music`), `Preferences.cardLines` (`mello-card-lines`, default 4, clamped 2...4); `OrientationLock.set(_ mask: UIInterfaceOrientationMask)`; debug launch arg `-partView names|music`.

Behaviour (from the spec, decided): one control row on top (name or "Rest", bar and value, `ValveView`, Hide, hold to check, tempo minus / number / plus, Names, Play or Stop); the card full width under it with the playing heads boxed in gold and the rest of the page dimmed (`Color.black.opacity(0.35)` with the boxes cut out, even odd fill); card number and dots under it; a gear button opening the existing controls (line, bars, sound, count in, loop, lines per card) as a sheet. `TabView(.page)` of cards; on `player.currentMeasure` change, turn to `LyreCards.index(holding:)`; a hand swipe while playing snaps back on the next slot change. Tap a notehead: `hear`; hold: `check`; tap a bar: `model.start(at:)` and, if playing, restart there; drag across bars: `start` at the first, `end` at the last, `loop = true`, bracket drawn over those spans. Rotate to landscape on appear, portrait on disappear and when switching to Names.

- [ ] **Step 1: Write the failing test** `testCardPreferencesDefault` in `PartModelTests`: fresh defaults give `partView == .music`, `cardLines == 4`; setting 7 stores 4, setting 1 stores 2.
- [ ] **Step 2: Run.** Expected: compile failure.
- [ ] **Step 3: Implement** the preferences, then the screen, then the orientation lock. Log `[CARD]` on: card turned (from, to, measure), hand swipe, tap note (name, bar), tap with no note, bar tapped, loop set, orientation change, strip render failure.
- [ ] **Step 4: Run** `PartModelTests` and the full suite in the background. Expected: PASS, 0 failures.
- [ ] **Step 5: Look at it.** `xcodegen generate`, build, quiet the simulator, then launch with `-startTab scales -openChart "<sample chart path>"`, again with PEAK and `-partFrom 27 -autoPlayPart YES`, and with `-checkNote 3`. Screenshot each with `xcrun simctl io ... screenshot`. Check: box on the right notehead, card turns at bar 36 on PEAK, note check scrolls and fits, Done returns to portrait, Names returns to portrait and shows the old list.
- [ ] **Step 6: Commit** `feat(cards): the chart as the director's own page, sideways, with the playing note boxed (#43)`.

### Task 6: Print lyre cards

**Files:**
- Create: `ios/Mellophone/Model/LyreCardPDF.swift`
- Modify: `ios/Mellophone/Views/CardView.swift` (Print in the gear sheet: three choices, then `ShareLink` or `UIActivityViewController` with the file)
- Test: `ios/MellophoneTests/LyreCardPrintTests.swift`

**Interfaces:**
- Consumes: `LyreCardPrint.layout`, `LyreCards.strip`.
- Produces: `enum LyreCardSheet: CaseIterable { case letter, a4, cards }` and `enum LyreCardPDF { static func make(chart: URL, score: Score, sheet: LyreCardSheet, title: String) throws -> URL }` writing to the temporary directory as `"<title> lyre cards.pdf"`. Letter is 612 x 792, A4 595.28 x 841.89, two cards stacked and centred, a thin grey cut line round each card; `cards` pages are exactly `cardSize`. The card's first bar number goes in 8 pt grey at the top right of the music area. Music is drawn by `CGContext.drawPDFPage` clipped to each strip, so it stays vector.

- [ ] **Step 1: Write the failing tests** on the card-turns fixture:
  - `testCardPagesAreCardSized`: `.cards` output has one page per printed card, each media box `504.57 x 379.84` within 0.1.
  - `testLetterHoldsTwoCardsPerSheet`: `.letter` page count `== ceil(cards / 2)`, media box 612 x 792.
  - `testNothingIsDrawnInTheRingStrip`: render each `.cards` page to a bitmap at 2x; every pixel in the top 62 points is white.
  - `testEveryBarIsOnACard`: the bar numbers printed on the cards, in order, are the first measures of the layout's cards, and the layout covers lines 0 to 6 once.
- [ ] **Step 2: Run.** Expected: compile failure.
- [ ] **Step 3: Implement.** Log `[CARD] printed N cards on M pages (sheet)` and errors on a page that cannot be opened.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Look at it.** Make PEAK's cards in the harness or a local test into the scratchpad, render every page, look: whole lines, nothing cut, top strip clear, staff about 6 mm. Never commit the output.
- [ ] **Step 6: Commit** `feat(cards): print a part as lyre cards for a flip folder (#43)`.

### Task 7: Prove it on Sam's chart and finish

**Files:**
- Modify: `ios/README.md` (section "The card view and printed cards (#43)"), `CLAUDE.md` (one bullet), the spec (what turned out different), `docs/superpowers/plans/2026-10-18-flip-folder-cards.md` (divergences recorded in place)

- [ ] **Step 1:** In the harness, render every PEAK card at the screen scale with every placed note's box drawn, and look at all of them; record any misplaced box as a reader bug and fix it in Task 1's code before going on.
- [ ] **Step 2:** Full test suite in the background; state the count and failures.
- [ ] **Step 3:** Retake the App Store screenshot of the chart screen from the sample chart (saved, not uploaded).
- [ ] **Step 4:** Docs and CLAUDE.md, then commit `docs(cards): the card view and printed cards (#43)`.
- [ ] **Step 5:** PR, merge, close #43 with files, results, divergences, follow ups and `[tokens: XXXk]`.

## Divergences recorded during the build

- Task 3: a test that a long part fills printed cards was added after the
  code, because the fixture's seven lines fit one printed card.
- Task 5: Done is an X in the row; the Names switch is in a shared Show
  section; the note check turns the phone upright; preferences are tested
  through the pure functions Preferences calls; the card is fitted to the
  height available.
- Task 6: the implementation was written before its tests and moved aside
  to watch them fail; the card label sits bottom right, not top right.
