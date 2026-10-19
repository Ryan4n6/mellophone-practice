# Flip folder card view: Sam's own page, played back with the note boxed

Status: approved by Ryan 2026-10-18 ("build it"), with printed cards added.
Mockup: PEAK bars 27 to 53 as one card, D4 in bar 34 boxed (sent to Ryan
2026-10-18, throwaway, not in the repo because the page is Sam's chart).

## Why

Sam (Ryan's son, mellophone, high school marching band) needs sight reading
practice. In marching band the music lives on lyre cards in a flip folder
clipped to the horn: a small card of four or so lines, flipped by hand while
playing. Ryan says Sam is usually reading songs he is **still learning** off
those cards, not ones he knows.

Today a chart plays back as rows of tappable chips that show only the note
name and octave ("D4"). That teaches the names and not the page. Ryan and Sam
want it the other way round: the music on a real staff with the playing note
highlighted, and the name, the fingering and the note check up top.

Success: Sam opens a chart he is learning, presses Play, and follows his own
part on something that looks like the card on his horn, with the note he
should be playing boxed and its valves shown, at a tempo he can keep up with.

## What Ryan decided

- A second way to view a chart during playback, selectable, alongside the
  current bar list.
- Real staff notation, the current note highlighted.
- Up top: the note name, its fingering, and how to check it against the horn.
- Four staves per card by default, scaled to look like a lyre card so it
  feels natural to a marching band kid.
- The songs he reads this way are ones he is still learning.

## Calls made in this design (Claude's, flagged for Ryan to check)

1. **The card is the director's PDF itself, cropped, not re-engraved.** The
   reader already finds every notehead's page, x and y. Showing the real page
   is the sight reading practice (it is the page he will read on the field),
   and re-engraving would mean drawing beams, ties, tuplets, dynamics and
   articulations ourselves, worse than the engraver did.
2. **A card is four systems (staff lines), stacked, in reading order across
   page breaks.** Card 3 of PEAK may be the last line of page 1 and the first
   three of page 2. Each system is cropped as its own strip and four strips
   are stacked. A page's title and footer are never on a card.
3. **The card view turns the phone sideways; the rest of the app stays
   upright.** Measured off PEAK on an iPhone 17: upright, the four lines fill
   402 points of width and a staff is about 2.2 mm tall, a third of print
   size. Sideways, packed the way lyre cards are engraved for small paper
   (tight margins, about 5 to 6 spaces between lines, no title), the same four
   lines fill 750 points and a staff is about 4.3 mm, close to a real lyre
   card. The controls collapse to one row across the top, like a video
   player: note, valves, Hide, check, tempo, Names, Play. The app is portrait
   only today (`project.yml` line 93), so this view alone asks for landscape.
   (Mockup: `lyre-mock-landscape.png`, 2026-10-18, sent to Ryan, not in the
   repo.)
4. **Music is the default view**, with a Music / Names switch. The choice is
   remembered (`mello-part-view`, `music` or `names`).
5. **The card turns itself** on the downbeat of the first bar of the next
   card, and can be swiped by hand. Dots under the card show which card is up.
   Swiping by hand while playing does not stop or move playback; the card
   jumps back to the playing card at the next note, the way a student's eyes
   come back to where the band is.
6. **The note name stays visible by default, with a Hide button** that hides
   the name and valves until he taps to reveal them. He is still learning the
   songs, so the crutch is on until he takes it away, the same choice the
   Trainer gives.
7. **Lines per card is a setting: 4 (default), 3 or 2** (`mello-card-lines`).
   Sideways, height is the limit, so fewer lines DO make each line bigger:
   three lines is about a third larger again. Whether four reads on a music
   stand is Ryan's and Sam's call on a real phone.
8. **A tap picks the nearest note left to right; the selected line picks the
   head.** At this size two heads of a chord are under 2 points apart, too
   close for a finger to choose between.
9. **Release:** this rides the next build after Ryan decides on build 6. Done
   means the App Store screenshots are retaken and saved; uploading them waits
   on Ryan's go, like the build.
10. **Tap a notehead on the card to hear it and put it in the top panel; hold
   it to open the note check**, the same as a chip does today. No new
   microphone caller: it is `NoteCheckView` with the existing purpose.

11. **Bars on the card are touch targets, the way PlayScore 2 does it.**
    Tapping the empty staff of a bar (not a notehead) starts playback there;
    dragging across bars sets the loop, which snaps to barlines and is drawn
    as a bracket over the card. The reader already knows every barline's x.
    Taken from PlayScore 2's published behaviour (red cursor, tap a bar to
    start, drag to loop), which Ryan pointed at on 2026-10-18. Ideas only:
    nothing of theirs is decompiled or copied.

## What PlayScore 2 actually does (read from its APK, 2026-10-18)

Version 1.5.70, pulled from Ryan's Pixel (installed from Google Play) and
decompiled in the scratchpad. Nothing of it is in the repo or will be.

- **It shows the original page.** A PDF is rasterised with PDFium at 2200 to
  3600 pixels wide (2900 by default) and the image is what you see.
- **Its reader works on pictures, not on the PDF.** `libReadScoreLib.so`
  (27 MB, native, no neural network in it) takes a bitmap and finds staves,
  stems, heads and beams geometrically, the same way ours does from the
  PDF's own glyphs. Text (titles, tempo words) goes through Google's on
  device OCR. Playback is a MIDI file through a SoundFont synth.
- **It knows bars, not notes, on the page.** Per bar it returns the left and
  right barline (x, bottom, height), the page, the first beat, the number of
  beats, where the first note sits as a fraction of the bar, and flags for
  repeats, first endings, segno, coda and multi-bar rests.
- **The red cursor is a straight sweep across the bar.**
  `x = offset + (1 - offset) * (beat - startBeat) / numBeats` of the bar's
  width. It does not sit on noteheads; in a bar of one whole note and four
  eighths the cursor runs evenly through all of them.

What this design does differently, on purpose: ours knows every notehead's
position, so the box sits ON the note being played, which a sight reading
student needs and a bar sweep cannot give. What PlayScore has that we
don't: it follows repeats, endings, D.S. and coda from those flags. That is
our known gap and stays a follow up, now with a reference for what to read.

## The other six (read from their APKs, 2026-10-18)

Sheet Music Scanner Pro, Opuscan (Flat), MuseScore, ScoreLens, PlayScan and
MobileSheets, pulled from Ryan's Pixel and read statically.

- **None reads the PDF's own symbols.** All seven turn a page into a picture.
  Four send it to a server to be read (Opuscan, MuseScore, ScoreLens,
  PlayScan); two read it on the phone (PlayScore, Sheet Music Scanner);
  MobileSheets reads no music at all.
- **Only Sheet Music Scanner marks the playing note on the real page.** It
  dims the page and redraws just that note's ink at full contrast, plus a
  light box on the bar. PlayScan and PlayScore sweep a bar. Opuscan,
  ScoreLens and MuseScore redraw the music and mark notes on their own
  engraving; MuseScore does not play a PDF at all.
- **Repeats:** every one that plays follows them; Opuscan does it most
  completely (repeat counts, voltas, D.C., D.S., To Coda, Fine, applied to
  one unrolled bar order, with orphan jumps thrown out first).
- **Brass:** no mellophone anywhere. Opuscan can print trumpet fingering
  text under notes; MuseScore grades a recording with a pitch model;
  ScoreLens knows treble clef euphonium. Nobody shows valves for the
  playing note on the real page, and nobody checks a held note.
- **Network:** every one but Sheet Music Scanner carries analytics or crash
  reporting, most several.

Taken into this design: the box stays, and **the page around it may be dimmed
so the playing note stands out** (Sheet Music Scanner's trick; we can do it
with the box alone, since we already know the notehead's bounds). Kept for
the repeats follow up: Opuscan's single unrolled bar order, and a
MobileSheets style hand placed jump ("from this note to that note") for when
the reader gets the road map wrong.

## Goals

- Follow along: during playback the sounding note (or chord, for the line
  being played) is boxed on the card, and the top panel shows its written
  name, its valves for the selected instrument, and a hold-to-check control.
- Turn the card at the right moment, every time, across page breaks.
- Tap and hold work on noteheads on the card.
- Everything the bar list does that matters to practice still works from
  this view: Play, Stop, tempo, count in, loop, the bar range, which line,
  the room sound.
- Works on every chart the reader reads: PEAK (Sibelius), Florida (MuseScore),
  the shipped sample chart, and the reader traps fixture.

## Non goals

- Re-engraving or redrawing music. No staff of our own on the card.
- Following repeats, endings and codas (already a known gap; the card plays
  the page straight through, same as now).
- Changing the Names view beyond the switch that leads to it.
- The web app. It has no chart import.

## Anti goals: it fails if any of these happen, even if it "works"

- **The box lands on the wrong note.** Worse than no box, because he will
  trust it and learn the wrong thing. A note the reader could not place gets
  no box and a log line, never a guessed one.
- **The fingering shown is not the derived one.** The top panel uses
  `Instrument` fingering for the selected horn, the one derivation, nothing
  stored per view.
- **A suspect bar is hidden or tidied.** It is shown on the card with the
  same suspect mark the list uses and played as read.
- **Sam's charts get into the repo or the build** as fixtures, screenshots or
  test images. Tests that need them stay in `Fixtures/local/` and skip when
  it is absent.
- Anything goes over the network.

## Printed lyre cards (Ryan, 2026-10-18)

Ryan: "make sure sam has a way to print a compatible format to fit his
marching band sheet holder". The holder is a ring flip folder: each clear
sleeve is **18.0 x 13.6 cm (7.08 x 5.35 in)**, landscape, on a frame of
18.6 x 15 cm, with two rings through a reinforced strip across the top of
the sleeve. Measured off the product photo: that strip covers the top
**2.0 cm** of the sleeve (65 of 449 pixels).

What gets printed is the same thing the card view shows: the director's own
lines, cropped to their ink, stacked tight, in reading order across page
breaks. Never redrawn music.

Calls made (Claude's):

- **Card size 17.8 x 13.4 cm** (7.0 x 5.28 in), 2 mm under the sleeve on each
  side so it slides in. Nothing printed in the top 2.2 cm (the ring strip)
  or within 0.4 cm of the other edges.
- **As many lines as fit at one fixed scale**, chosen once per chart so every
  card's staff is the same size: the widest line fills 17.0 cm. For PEAK that
  is 5 or 6 lines a card (a staff about 6 mm tall), which matches the
  product photo. A line is never
  split across cards. The card's first bar number is printed small in the
  top right of the music area, so a dropped stack can be put back in order.
- **Two outputs from one Print button on the chart screen:**
  - *Letter, two cards per sheet, with cut lines*, for a home printer
    (two 13.4 cm cards stack in 27.9 cm). A4 the same way.
  - *Card size pages*, one card per page, for a print shop or a printer that
    takes card stock.
- **It goes out through the iOS share sheet** (AirPrint, Save to Files,
  AirDrop). Nothing goes over the network from the app; AirPrint is the
  user's own printer on their own network.
- The PDF is built on the phone from the user's copy of the chart with
  `CGPDFPage` drawing into a PDF context, so the music stays vector and
  prints sharp.

Checked by: building the PDF for PEAK and for our own fixtures, rendering
every card, and looking at them; measuring the card size and the clear top
strip in the output; a test on our own fixture that no line is cut and none
is skipped (the bars on all cards together are every bar of the chart, in
order).

## Constraints from the project (see CLAUDE.md)

- One `PartPlayer`, owned by the charts card. The card view watches the same
  player the list does; it never makes a second.
- `PartTimeline` decides what sounds when; the card reads the timeline's
  current entry to know what to box. It does not keep its own clock. Beat
  dots and haptics already read the audio clock, and the box must too, or it
  drifts against the sound.
- The microphone stays on one screen only.
- Retake the App Store screenshots: the chart screen changes. They show the
  sample chart.
- Definition of done applies: issue first, `[CARD]` logging on success and
  failure paths, why comments, tests with results stated, README and
  CLAUDE.md updated.

## What has to exist (the parts already decided)

### The reader keeps where every note was printed

`ScoreBuilder.readNotes` already holds the notehead glyph (page, x, y) and its
system at the moment it makes each `ScoreEvent` (around `ScoreBuilder.swift`
line 743, and for rests around 656 and 671). Today it throws them away. It
keeps them:

- each `ScoreEvent` gains an optional placement: page index, the system's
  index in reading order, and the notehead's x and y in PDF user space (y
  up). Rests carry the rest glyph's position when there is one.
- `Score` gains the systems in reading order: page index, the five line ys,
  the x range, and the first measure on that line. This is what cards are cut
  from.

Every pitched event on PEAK, Florida, the sample chart and the traps fixture
must come out with a placement. One without is a reader bug to log, not a
case for the view to paper over.

### Cutting a system strip (lyre card packing)

A strip runs the full width of the system's x range plus a margin, and high
and low enough that nothing printed for that line is cut off: ledger notes up
to C6 (5 half spaces over the top line) and down to F#3, tempo marks (which
sit about 12 half spaces over the top line, #41), dynamics, rehearsal
letters, and dynamics under the line (an `ff` reaches past 5 half spaces under
the bottom line on PEAK, and the mockup's fixed 5 cut it). So the bounds come
from the ink actually assigned to that system, not a fixed margin, and strips
are then stacked with no gap of their own: the director's spacing between
lines is the thing a lyre card throws away. Strips may overlap a neighbour's ink a little; cutting a note off is
worse than showing a sliver of the next line. Measure the bounds on PEAK and
Florida, render the strips, and look at them.

Strips are drawn from the user's own copy of the PDF in Application
Support/Charts with `CGPDFPage`, at screen scale, and cached for the life of
the screen.

### The box

The box is drawn from the notehead's placement converted into the strip's
coordinates (flip y, subtract the strip's origin, scale). Sized from the
system's half space, about a notehead and a half wide. Gold, matching the app.
When the line being played is Both, every head of the chord is boxed.
During a rest, the rest is boxed if it was placed and the top panel says
Rest, as it does now. Whole bars of rest keep the on screen count the list
already shows.

### The top panel

Written name (`writtenName`, the page's spelling), the valves for the selected
instrument drawn with `ValveView`, the bar number and note value, a Hide
control, and hold-to-check. Out of range notes show the name greyed, as the
list does.

### Screen layout, sideways

One control row across the top (note name, bar and value, valves, Hide,
hold to check, tempo minus / number / plus, Names, Play or Stop), the card
full width under it, the card number and dots under the card. On an iPhone
17 the card is about 310 points tall in 750 wide. The title, the
`InstrumentChip`, Done, and the less used controls (line, bars, sound, count
in, loop) go behind one button that opens them as a sheet. The Names view
stays upright as it is today.

## Left to the builder

- How strips are cached and when they are rendered.
- The flip animation and the swipe gesture details.
- Hit testing radius for a tap on a notehead, as long as a tap between notes
  does nothing (same rule as the list).
- Accessibility labels for the card ("D4, bar 34, half note").
- How the view is split across files.

## How it is checked (measure, do not reason)

- Render every card of PEAK and Florida in the scratch harness with every
  note's box drawn, and look at all of them: every box on its notehead,
  nothing cut off at a strip edge, cards turning at system boundaries in the
  right order across page breaks.
- Tests (committed, on our own charts only): every pitched event of the
  sample chart and the traps fixture has a placement inside its system's
  strip. Card turns and a card that crosses a page break need a chart with
  more than one card, and none we own has one (traps and the sample chart
  are one page, Florida is four lines), so a NEW self authored fixture is
  added: `card-turns.musicxml` and its MuseScore PDF, two pages, at least six
  systems. `reader-traps` stays as it is, because `ChartReaderTrapsTests` pins
  it bar by bar.
- Local tests (skip without `Fixtures/local/`): every pitched PEAK and
  Florida event is placed; PEAK page 1's lines start at bars 1, 11, 20, 27,
  36, 42, 49, 54 and 65, so bar 34 is on card 1 and bar 65 opens card 3.
  (The mockup labelled bars 27 to 53 "card 3 of 9"; that was a picture, not
  this rule. Cards are counted in fours from the first line.)
- Simulator: open the sample chart and PEAK with `-openChart`, play, and
  screenshot the box following and the card turning (`-partFrom` near a card
  boundary). State plainly what was hand-built and what was not seen on a
  phone.
