# Reading the director's PDFs and playing them back

Design for issue #19. Written 2026-09-06.

## The problem

Sam gets his marching charts as PDFs in the band director's OneDrive. He cannot
tell what a part sounds like by reading it. Everything else in this app teaches
one note at a time; nothing helps with the page he is actually handed at
rehearsal.

## Why this is not optical music recognition

Both charts examined are digitally engraved. The notation is embedded as
positioned font glyphs with a `ToUnicode` CMap, and neither file contains a
single raster image. There is nothing to recognise. You read the content stream
operators and the glyphs tell you what they are.

`Florida Fight Song (Orange and Blue)-Horn in F.pdf`, MuseScore 4, font `Leland`,
maps to SMuFL: `E0A4` noteheadBlack, `E0A3` noteheadHalf, `E050` gClef,
`E260`/`E261`/`E262` flat/natural/sharp.

`PEAK mello.pdf`, Sibelius, fonts `OpusStd` and `OpusSpecialStd`, maps to legacy
Petrucci codes instead: `U+0153` filled notehead, `U+0152` void notehead,
`U+0077` whole note, `U+0026` treble clef, `U+0062`/`U+0023`/`U+006E` for
flat/sharp/natural.

Two engravers, two tables, one algorithm. A throwaway spike read pitches out of
both. Staff lines fall out of the horizontal vector rules at even spacing
(4.96pt, five lines, dead even in the MuseScore file), every notehead sits
exactly on a line or exactly halfway between two, and staff position converts to
pitch by arithmetic.

The cost of this approach is that it is all or nothing. A PDF whose notation has
been flattened to vector paths carries no glyphs and yields nothing. Two music
PDFs on the build machine are exactly that. The app must detect this and say so
plainly rather than produce a bad transcription.

## Constraints

These are the repo's existing hard constraints, and none of them bends here.

- **Nothing over the network.** `CGPDFScanner`, `CGPDFContentStreamCreateWithPage`
  and `CGPDFDocument` are in the SDK. No SPM package is added, no `URLSession`
  enters the target, and the App Store privacy label stays "Data Not Collected".
- **No accounts.** OneDrive registers a File Provider extension, so `.fileImporter`
  reaches the band folder and iOS handles authentication. No MSAL, no Entra app
  registration, and no school-district admin consent, which Microsoft has required
  for third-party apps touching OneDrive data since mid-2025.
- **`contentRightsDeclaration` stays `DOES_NOT_USE_THIRD_PARTY_CONTENT`.** The app
  ships no music. The user supplies it. This also governs test fixtures; see
  Testing.

## Non-goals

- No recognition of scans, photos, or vector-flattened PDFs. Out of scope, and
  the app says so rather than guessing.
- No OneDrive sync, folder browsing, or background refresh. That is a different
  app and belongs back in issue #2.
- No General MIDI playback. Playback uses the app's own brass tone so an imported
  part sounds like the rest of the app.
- No editing or re-export. This is a practice tool, not a notation editor.

## Architecture

New directory `ios/Mellophone/Import/`. Four units with one job each, arranged so
that PDF knowledge and music knowledge never mix.

### `PDFGlyphReader`

In: a `CGPDFPage`. Out: `PageGeometry`.

Walks the content stream with `CGPDFScanner`, maintaining the graphics state
stack (`q`, `Q`, `cm`) and the text state (`BT`, `ET`, `Tf`, `Tm`, `Td`, `Tj`,
`TJ`), and resolves every glyph and every path to page coordinates.

```swift
struct PlacedGlyph { let scalar: UInt32; let x, y, size: Double; let font: String }
struct PlacedPath  { let vertices: [CGPoint]; let filled: Bool; let bounds: CGRect }
struct PageGeometry { let glyphs: [PlacedGlyph]; let paths: [PlacedPath] }
```

It knows PDF and knows nothing about music. It does not decide what a path is.
That matters: staff lines, stems, beams, barlines, ledger lines, slurs and
hairpins are all paths, and telling them apart is a music question.

Glyph scalars come from each font's `ToUnicode` CMap, read from the page's font
resources. Fonts whose `BaseFont` is not a known music family are ignored, which
drops the title, tempo marks and rehearsal letters without extra work.

### `MusicFontTable`

In: a `BaseFont` name and a scalar. Out: a `MusicSymbol`.

```swift
enum MusicSymbol: Equatable {
    case noteheadBlack, noteheadHalf, noteheadWhole
    case gClef, fClef
    case sharp, flat, natural
    case augmentationDot
    case flag(count: Int, up: Bool)
    case rest(value: Int)          // 1 = whole, 2 = half, 4 = quarter, ...
    case timeSigDigit(Int)
    case unknown(UInt32)
}
```

Pure data plus a lookup, one table per engraver family: SMuFL for `Leland`,
`Bravura` and `MScore`; Petrucci codes for `Opus`; Maestro for Finale. Adding an
engraver is adding a table, never a code path. `unknown` is retained rather than
discarded so an unrecognised chart can report which codepoints defeated it.

### `StaffFitter`

In: `[PlacedPath]`. Out: `[StaffSystem]`.

Selects thin wide horizontal fills, groups them into runs of five at even
spacing, and emits `StaffSystem { topLineY, halfSpace, xRange, pageIndex }`.
Pure geometry, no music vocabulary. Rejects any group whose line spacing varies
by more than a small tolerance, which is what keeps hairpins and text underlines
out.

### `ScoreBuilder`

In: `PageGeometry`, `[StaffSystem]`, a `MusicFontTable`. Out: `Score`.

This is where the music knowledge lives, in ordered stages:

1. **Assign** each glyph and path to the system whose band contains it, allowing
   for ledger lines above and below.
2. **Read the head** of each system: clef, then the run of accidentals that forms
   the key signature, then the time signature digits.
3. **Classify paths**: thin vertical fills adjacent to a notehead are stems;
   thick sloped fills spanning stem ends are beams, and the number stacked gives
   the subdivision; full-height vertical fills are barlines.
4. **Group noteheads into chords** by x position, which is also how divisi is
   detected. The Florida chart is two voices on one staff; `PEAK mello.pdf` is
   monophonic. Both must work.
5. **Resolve pitch**: staff step from y, then key signature, then any inline
   accidental immediately to the left, which persists to the end of the measure.
   The result is looked up in the existing `Note` table so the whole app agrees
   on spelling, frequency and staff position.
6. **Resolve duration**: notehead type gives whole, half, or "quarter or
   shorter"; flags and beams resolve the rest; augmentation dots multiply.
7. **Order** systems top to bottom within a page and pages in order, producing one
   continuous event stream with rests filled in.
8. **Validate** every measure (see below).

### `Score`

```swift
struct ScoreEvent {
    let note: Note?              // nil for a rest, or for an out of range pitch
    let outOfRangeName: String?  // set only when the pitch is outside F#3 to C6
    let onsetBeats: Double     // from the start of the score, not the measure
    let durationBeats: Double
    let measure: Int
    let voice: Int
}

struct Score {
    let events: [ScoreEvent]
    let timeSignature: (beats: Int, unit: Int)
    let keySignature: Int        // negative flats, positive sharps
    let voiceCount: Int
    let suspectMeasures: Set<Int>
    let unreadableSymbols: [UInt32]
}
```

`note` is an existing `Note`, not a new pitch type, so `fingeringFor`,
`staffPosition` and `frequency` all come along for free and the imported part
renders on the same staff as everything else.

## The check that makes it trustworthy

**Durations in a measure must sum to the time signature.**

This is the same idea as `verifyFingerings()` re-checking the fingering
derivation in the browser on every load, and as `check-instruments.js` refusing
to run when the stored table disagrees with the derivation. A measure that does
not sum is a measure the reader got wrong. It goes into `suspectMeasures`.

Suspect measures render visibly flagged and are tappable to correct by hand. The
app does not silently play a guess and does not refuse the whole file over one
bad bar. Issue #9 is the precedent: a wrong fingering teaches the wrong thing,
and so does a wrong rhythm.

## Error handling

Every failure is named to the user in plain language, and every one is logged
with a greppable `[IMPORT]` prefix through the existing `Log` and, in debug,
`FileLog`.

| Condition | Behaviour |
|---|---|
| File will not materialise from OneDrive | `startAccessingSecurityScopedResource()` plus an `NSFileCoordinator` read; on failure, tell the user to mark it available offline in OneDrive |
| PDF has no embedded music font | "This PDF has no readable notation in it." Offer nothing false |
| Music font present but no family table matches | Same message, plus the `BaseFont` name in the log so a table can be added |
| No staff systems found | "Could not find a staff on this page" |
| Some measures fail the sum check | Import succeeds, those measures are flagged |
| Note falls outside F#3 to C6 | Kept with its duration and its name in `outOfRangeName`, shown greyed. It must never collapse to `note == nil` and read as a rest: the part would then sound right apart from the bars Sam most needs to hear |

## Playback

`ScalePlayer.render` already lays notes into one buffer at exact sample offsets
and is covered by `ScalePlayerTests` and `ScalePitchTests`. It assumes one fixed
`interval` for every note.

Extract the renderer into a function taking explicit events:

```swift
static func render(events: [(frequency: Double, onset: Double, duration: Double)],
                   volume: Double, format: AVAudioFormat) -> AVAudioPCMBuffer?
```

`ScalePlayer` then becomes a caller that maps a scale onto evenly spaced events,
so there is exactly one tested renderer and the scales path keeps its existing
behaviour and tests. The peak normalisation and the summing of overlapping
releases stay where they are.

Long parts must not render as one enormous buffer. A four-page chart at a slow
tempo is several minutes of audio, so playback renders in chunks of a few bars
and schedules them back to back with `at: nil`, which is the same discipline
`Metronome` uses and for the same reason: never schedule against an absolute
player timeline.

## Testing

**Fixtures must be self-authored.** The repo is public and the app declares
`DOES_NOT_USE_THIRD_PARTY_CONTENT`. Sam's charts are copyrighted arrangements and
do not go in git. Instead, author short exercises in MuseScore and in Sibelius,
export PDFs, and commit those. Ground truth is then known exactly because we
wrote it.

Sam's real charts stay local and gitignored, and are used for manual spot checks
only.

- `PDFGlyphReaderTests`: a fixture with known glyph positions, asserted to the
  point.
- `MusicFontTableTests`: both tables asserted against the codepoints recorded in
  issue #19.
- `StaffFitterTests`: five evenly spaced rules become one system; four do not;
  unevenly spaced rules do not.
- `ScoreBuilderTests`: for each fixture, assert every pitch and every duration
  against the notation we authored.
- **A negative control**, in the spirit of `ScalePitchTests`: deliberately corrupt
  one notehead's y position and one measure's rhythm, and assert the reader
  reports the wrong pitch and that the corrupted measure lands in
  `suspectMeasures`. A validator nobody has watched fail is not a validator.
- `ScalePlayerTests` must keep passing unchanged after the renderer is extracted.
  That is the regression guard on the refactor.

## Phases

Phases 1 and 2 are one implementation plan: they build and prove the reader, and
neither is shippable alone. Phase 3 is a second plan and the first one a user
sees. Phase 4 is a separate decision, not a commitment.

1. `PDFGlyphReader`, `MusicFontTable`, `StaffFitter`, and pitch with key signature
   and accidentals. The measure-sum validator arrives with this phase because it
   is the test harness for everything after it.
2. Rhythm: flags, beams, dots, rests, ties.
3. Practice UI: import via `.fileImporter`, the part on the existing staff with
   per-instrument fingerings, voice picker for divisi, loop a bar range, tempo
   scaling, count-in from the metronome.
   **Shipped 2026-10-09**, built directly from this document. Where it landed
   differently from what is written above:

   - **The part is shown as bars of note names with fingerings, not as
     engraving.** The pinned staff draws the ONE note sounding now, which is
     what `StaffView` already does and is tested for. Drawing the whole part as
     notation would mean laying out beams, stems and spacing, and a rhythm the
     reader got wrong would then be drawn wrong with total confidence. Chips
     are wider for longer notes, so a bar still has the shape of its rhythm.
   - **Suspect measures are flagged and NOT correctable by hand.** "Tappable to
     correct" above contradicts the non-goal "no editing", and the non-goal
     wins for now: the bar is outlined in red, counted in a warning, and still
     played, with the screen saying to trust the page over the app. Hand
     correction needs a way to enter a rhythm, which is a notation editor.
   - **Tempo is the student's number.** The reader drops tempo text on purpose,
     so there is no marked tempo to scale. The screen offers 40 to 220 and says
     what the number counts, which `Pulse` works out from the time signature:
     a dotted quarter in 6/8, not an eighth.
   - **`Score` gained `beatUnits`.** `durationBeats` counts in each measure's
     own unit, so a part that moves between 4/4 and 6/8 could not be played at
     a steady eighth without knowing where. Found while writing playback, not
     by a chart: both of Sam's are in quarters throughout.
   - **Charts are copied into the app.** The design said only "import via
     `.fileImporter`". A picked OneDrive address stops working on the next
     launch, so the PDF is copied to Application Support and listed. Still no
     network, no account, and nothing the app shipped with.
   - **Out of range notes are SOUNDED**, not only shown greyed. The table has
     no row for them but the name is still a pitch.
   - **The count-in is the metronome's click rendered ahead of the part**, not
     the running `Metronome`. Starting the real one would tie a part's first
     note to a clock, which is the thing the playback design forbids.
4. `index.html`, later and possibly never. Reading operators is far less code
   than rendering, so a raw parser plus `DecompressionStream` is a few hundred
   lines rather than the megabyte pdf.js would cost, but the web version is the
   fallback product and this is not why it exists.

## Risks

- **Engraver coverage.** Two of two charts read so far, from two different
  programs. Finale's Maestro is the obvious third table and is untested. More of
  Sam's charts would settle this and cost a minute each.
- **Beams are the hardest part** and the one piece with no glyph to lean on. If
  beam geometry proves unreliable, the fallback is to accept "quarter or shorter"
  from the notehead and let the measure-sum validator distribute the remaining
  duration, flagging the measure. Degraded, honest, still useful.
- **Repeats, first and second endings, D.S. and coda** change the playback order
  and are not addressed in phases 1 and 2. Until they are, the app plays the page
  as written, top to bottom, and should say so.
