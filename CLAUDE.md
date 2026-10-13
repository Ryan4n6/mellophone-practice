# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A practice tool for the mellophone, the French horn, the trumpet and the euphonium: harmonic series, scales, note recognition drill, metronome, practice timer, practice log, fingering chart.

There are now **two products in this repo**, and they are built to different rules:

Both products are called **Honk It Up!** (#12). The Xcode target and this repo are still named for the mellophone, which is history, not the product name.

- **The web app**, `index.html`, is the whole original tool in one file (markup, styles, script, in that order). It stays live and is the fallback for anyone on Android or a Chromebook. Everything under "Hard constraint" and "Architecture" below is about this file.
- **The iOS app**, `ios/`, is a native SwiftUI app that treats `index.html` as its functional specification. It is not a web view wrapper, and the reasons are in issue #2 and `ios/README.md`. Read `ios/README.md` before touching anything in `ios/`.

The data tables in `index.html` (`NOTES`, `SCALES`) are the source of truth for **both** products. Every `SCALES` entry carries a required `desc`, a plain-English line saying what the exercise is and why you would play it: the names are the words a band director says out loud and mean nothing to a fifteen year old who has not heard them yet, so the name stays and the description explains it (#15). Every note in a scale renders with its fingering for the selected instrument, because a fingering app that shows a student a bare list of letters is not doing its job. An exercise played on ONE valve combination carries `hold` and shows that instead: E5 is open on a mellophone AND is the sixth partial of the 1+2 series, so a 1+2 lip slur showing the chart answer tells a student to lift their fingers mid-slur (#16). The chart fingering and "can I play this note with these valves down" are different questions.

**The audio is tested by ear, arithmetically** (`MellophoneTests/ScalePitchTests.swift`). Every other audio test checks the sound is present and well behaved; none would notice the app playing A440 for every note of every scale. This one measures the fundamental of each rendered note with a YIN detector and names it back, to 15 cents. Two rules it was built under: the detector is calibrated against synthetic tones of known pitch BEFORE it is allowed to judge the app (plain autocorrelation locks onto subharmonics and reported octave-down errors that looked exactly like the app playing wrong notes), and a negative control proves a deliberately swapped note is actually caught. A correction goes into `index.html` first, then gets carried into the Swift model with `python3 ios/scripts/sync-note-data.py`.

**The fingering chart is derived, not remembered, in both products.** Open notes are written C4, G4, C5, E5, G5, C6; everything else is the nearest partial above it lowered by valves (2 = 1 semitone, 1 = 2, 1+2 = 3, 2+3 = 4, 1+3 = 5, 1+2+3 = 6). Three valves reach six, which is why the lowest note is F#3 and not F3. The generator refuses to run if the table disagrees, `FingeringChartTests` asserts the same about the shipped data, and the web app's `verifyFingerings()` re-checks it in the browser on every load and logs `[FINGERING]`. Seven rows were wrong once (#9) and the drill prints fingerings as corrective feedback, so a wrong value teaches the wrong thing.

**Fingerings are per-instrument and derived, never stored per instrument** (`Model/Instrument.swift`, and its twin `INSTRUMENTS` / `fingeringFor` / `scaleDisplayName` in `index.html` since #11). Mellophone and trumpet share a chart; French horn does not, because its F side sits an octave lower in the harmonic series, so written E4 is open on horn and `1+2` on the other two. Scale names store the WRITTEN key as fact and compute the concert half, since written F is concert Bb on an F instrument and concert Eb on a trumpet. `InstrumentTests` pins all of it against two published charts, verified note by note on 2026-08-20 and agreeing on all 31 notes in range: Brian Kay's *Intermediate Trumpet Method* chart (brassstages.com/acrobat/trumpetchart.PDF), which is laid out by overtone series and shows E5 in both the open and the 1-2 column, and the Mouthpiece Express *Single F French Horn Basic Fingering Chart* (starcitymusic.com). **Render the PDFs and read them; do not trust a search summary.** The first summary returned for the horn chart said written E4 is fingered 2 and D5 is 1+2, and the actual chart gives both as open, which is what this app says. **The euphonium is the treble clef one** (#25): the trumpet's chart, sounding a major ninth (14 semitones) under the page, pinned against the Mouthpiece Express euphonium chart, which is printed in bass clef at concert pitch and agrees on all 31 notes read a ninth up. A bass clef euphonium is NOT a fifth instrument row: it needs a bass clef staff in both products and in the chart reader, and until those exist do not add one that shows treble clef names to a bass clef reader. It pins the Same Fingering card's grouping too (`Note.sameFingering(on:)`, in `Instrument.swift` next to the derivation, called by the Trainer rather than reimplemented there; #13). The two implementations are the same derivation on purpose: change one and change the other.

**Range:** F#3 to C6 is the instrument's span and what is expected of a drum corps lead player. The practice range defaults to C4 to G5, which is where a high school player lives.

## Commands

The web app has no build, no bundler and no package manager. It has one check script, which is developer tooling and never ships.

- Run it: `open index.html` (or drag it into a browser).
- Check the fingering derivation: `node scripts/check-instruments.js`. Same published trumpet and Single F Horn charts `InstrumentTests` uses on the iOS side, plus the stored `NOTES` table. Run it after touching `NOTES`, `SCALES`, `INSTRUMENTS` or `fingeringFor`.
- Deploy: push to `main`. GitHub Pages serves the repo root at https://ryan4n6.github.io/mellophone-practice/.

## Hard constraint: nothing loads over the network

No CDN scripts, no external stylesheets, no web fonts, no remote images, no fetch. The point of the app is that it works in a band room or on a bus with no signal, so every asset must be inline. The treble clef is inline SVG path data, drawn twice because each staff carries its own copy of the block (#14); the accidentals are still Unicode glyphs in a generic `serif`, and the UI font is the system stack. The clef artwork and its placement are shared with the iOS app: `ios/scripts/treble-clef.svg` is the source, `ios/scripts/make-treble-clef.py` regenerates the Swift, and the `<g transform>` in `index.html` carries the same scale and translate. A G clef is only a G clef if its spiral sits on the G4 line, y=120 in both products, so those numbers are measured rather than nudged. Do not introduce a dependency that requires a build step or a request, and do not split the file.

## Architecture

### `NOTES` is the source of truth

One array of `{ name, freq, staffPos, finger, accidental }` at the top of the script drives everything downstream: the fingering chart, the range dropdowns, the drill pool, the harmonic-series card, and scale playback (scales store note *names* and look them up in `NOTES`). Adding or correcting a note means editing that one row.

- `freq` is the literal frequency of the named pitch. No F-transposition is applied to audio. The mellophone's transposition shows up only in the `SCALES` labels, which name both ("Concert Bb (Written F)").
- `finger` is the stored mellophone chart and the thing `verifyFingerings()` checks the derivation against. Nothing renders it directly any more: the trainer label, the chart rows, the drill's corrective feedback and the "Same Fingering (Harmonic Series)" card all call `fingeringFor(name)` for the selected instrument, and that card groups by the derived value because a horn's longer open series separates notes a mellophone cannot. The strings are still equality keys and still light the valve diagram via `finger.includes('1'|'2'|'3')`, so they must be written consistently: `"1+2"`, never `"2+1"`.
- `NATURAL_NOTES` is `NOTES` minus flats that have a sharp enharmonic at the same frequency. Use it for anything the user picks from (range selects, fingering chart); use full `NOTES` for lookups, drills, and enharmonic matching.

### `staffPos` is a staff coordinate, not an SVG y

`staffPos` counts diatonic steps down from the top of the drawing area in units of 10 (C6 = 0, F3 = 180), and `drawNoteOnStaff` converts it with `y = staffPos * 0.5 + 30`. Enharmonic pairs deliberately get *different* `staffPos` values (F#3 sits on the F line, Gb3 on the G line), which is why the table has separate rows for them. Stem direction flips at `y < 100`, and the four ledger lines are pre-drawn in the SVG and toggled by `visibility`.

### Two staves, one draw function

The trainer and the drill each have a full copy of the staff SVG with the same element ids, distinguished by a prefix: `''` for the trainer, `'d-'` for the drill. `drawNoteOnStaff(svgId, note, prefix)` takes that prefix. A third staff means duplicating the SVG block with a new prefix and passing it through.

### Panels and global handlers

Five tab panels (`#panel-trainer|scales|drill|metro|timer`) toggled by a single `.active` class; the fingering chart card sits below all of them and is always visible. Every handler is a global function invoked from an inline `onclick` in the markup. Two of them, `showPanel` and `setTimeSig`, read the implicit global `event` to find the button that was clicked, so converting the file to a module or to `addEventListener` will silently break tab and time-signature highlighting.

### Audio

One lazily created `AudioContext` shared by everything (`getAudioCtx`), created on first user gesture so autoplay policy is satisfied. `playTone` builds a fresh sawtooth oscillator into a lowpass filter into a gain node per note, with a filter sweep and an ADSR for a brass-ish attack; volume comes straight off the `#volume` slider. The metronome is a separate sine blip (1200 Hz on beat 1, 800 Hz otherwise) scheduled with `setInterval`, not the WebAudio clock, so it drifts at length. Changing tempo tears down and rebuilds the interval.

### Persistence

`localStorage`, keys prefixed `mello-`: `mello-range-low`, `mello-range-high`, `mello-instrument`, `mello-scale-speed`, `mello-practice-log`. `mello-instrument` holds the same raw values the iOS app uses (`mellophone`, `frenchHorn`, `trumpet`) and falls back to mellophone with a `[INSTRUMENT]` console error if it holds anything else. The practice log is a JSON array of `{date, seconds}`, newest first, capped at 50 entries. Note that `mello-scale-speed` is written by `saveScaleSpeed` but never read back on load, so the speed select does not actually persist. `saveSession` silently ignores sessions under 10 seconds.

## The iOS app (`ios/`)

Full detail is in `ios/README.md`. What matters before you touch it:

- **`ios/project.yml` is the source of truth**, not `Mellophone.xcodeproj`. The project is generated by XcodeGen and is committed only so a clone opens in Xcode. Anything hand-edited in the pbxproj is silently reverted by the next `xcodegen generate`, and the drift stays invisible until an upload fails. That includes `CURRENT_PROJECT_VERSION`.
- **Several build settings are load-bearing and were paid for with real App Store failures** in the sibling repo `Ryan4n6/TPS-iOS`. Each is commented in `project.yml` with the outage it prevents. Do not tidy them away. The expensive one is `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO`, without which every build lands as "Missing Compliance", invisible to TestFlight testers.
- **The microphone is on for one screen only** (the note check, #22), and what it hears is measured and dropped: no file, no recording, nothing kept past a tenth of a second. That is what keeps the "Data Not Collected" label true. Do not add a second caller of `PitchListener`, and do not let it run in the background. The tuner (#32) is that same screen opened from the Trainer, not a second one: a new thing that needs to listen gets a `NoteCheck.Purpose`, not a listener of its own.
- **Nothing goes over the network, ever.** No accounts, no analytics, no crash reporting SDK, no ads, no `URLSession`. The users are likely to include minors, the privacy label reads "Data Not Collected", and there is no backend. If a feature seems to need a server, that goes back to issue #2 as a decision, it does not get implemented.
- **The metronome's timing is the product.** `Audio/BeatSchedule.swift` computes every beat from a fixed anchor (`beat(i) = anchor + round(i * period)`) rather than by advancing a cursor, because an accumulating cursor is what makes the web version drift. `MellophoneTests/BeatScheduleTests` measures the difference. If you change that file, run those tests.
- **The scheduler never asks what time it is.** Beats are scheduled back to back with `at: nil`, four queued at a time, and each buffer is one whole beat long so its LENGTH places the next beat. The earlier design queued beats falling inside a lookahead horizon computed from `player.playerTime`; when that clock stalls the horizon freezes, nothing is queued, the player has nothing to render, and its clock never advances. A deadlock where each half waits on the other. Do not reintroduce absolute scheduling against the player timeline.
- **Do not trust `engine.isRunning`, and do not delete the stall watchdog.** When the device locks, the audio graph stops rendering while every indicator reports health: `isRunning` stays true, the session reactivates without error, the device render clock keeps advancing, the player reports playing with a full queue. The only honest signal is whether the player's sample time advances. `Metronome.detectAndRepairStall` rebuilds the graph after half a second of no movement, and without it the click dies every time the phone goes dark. The full evidence table is in `ios/README.md`.
- **A debugger changes the answer.** `devicectl --console` holds the process alive, which made a broken background feature look like a working one and got issue #3 closed on invalid evidence. Anything involving suspension has to be diagnosed from a file the app writes itself (`FileLog`), launched from the home screen with nothing attached.
- **Haptics are foreground only.** CoreHaptics will not play backgrounded or locked. That is iOS, not a gap here, and the toggle's subtitle says so.
- **Beat dots and haptics read the audio clock**, they do not run their own timer, so the display cannot drift against the sound.
- Debug builds show a live timing readout at the bottom of the Metronome tab: beats, audio-clock vs wall-clock elapsed, skew, worst schedule error. That panel is how timing claims get answered with a measurement instead of an assertion.

### Running it on hardware

`bash ios/scripts/run-device.sh` builds, signs headlessly against the Massfeller LLC App Store Connect key, installs and launches with `--terminate-existing`. That last flag matters: installing over a running app does not restart it, so without it you screenshot the old build.

### Imported charts

A student's own part, read from the director's PDF and played back (#19). Entry
is the "Your Charts" card at the top of the Scales tab, because all five tabs
are taken and a sixth becomes a "More" list.

- **`PartTimeline` decides what sounds when, `PartPlayer` only queues it.** The
  timeline is pure arithmetic and is where a playback bug should be reproduced
  as a test first. The player renders a few bars at a time and queues them two
  deep with `at: nil`. Do not schedule a part against the player's clock, for
  the same reason as the metronome.
- **`durationBeats` is in the measure's own unit**, an eighth in 6/8 and a
  quarter in 4/4. Convert through `Score.beatUnit(of:)` bar by bar. One factor
  for the whole part plays a meter change at the wrong speed.
- **A nil `note` is not a rest.** An out of range pitch has no table row and
  still sounds; `PartTimeline.frequency(of:)` is the one place that decides.
- **A chart opens at the first bar with a note in it** (`PartModel.entrance`),
  not at bar 1, and whole bars of rest are counted on screen from
  `PartTimeline.beat(at:)`. A student alone has no band to count against.
- **A part is rendered as phrases.** `PartTimeline.phrased` marks which notes
  run together and `TonePlayer.render(articulation:)` joins them with a 10 to
  14 ms dip in place of the 100 ms hole a scale note leaves. Scales still use
  `Articulation.separate`, the old path. No glide and no pitch drift: a note
  may arrive from a few cents under and is then exactly on pitch.
- **The engine's main mixer is made before the engine starts**
  (`AudioEngineHost.start`). Do not remove that line: an effect chain wired
  into a mixer made on a running engine leaves its player disconnected. The
  part's reverb (`PartRoom`, `mello-part-room`) is mono in, stereo out, and is
  bypassed for Dry.
- **A chart plays at the pitch the selected horn makes** (#24), a fifth under
  the page on a mellophone or F horn, a tone on a trumpet, a ninth on a
  euphonium, so a student can play along. `Instrument.sounding` is the one
  place the factor lives and the note check uses the same one.
  `PartTimeline.Entry.frequency` stays the WRITTEN pitch (staff, valves and
  the note check read it); only `chunks` and the tapped note are lowered, and
  both hold the filter open to 700 Hz like "Hear it". A timeline built with
  no instrument renders the page as written and is for layout and tests only:
  `PartModel.prepare` takes the instrument with no default on purpose. The
  Trainer, the scales, the drill and the web app still play written pitch.
- **A tap on a note sounds it and puts it on the staff** (`PartModel.pick`,
  `PartPlayer.sound`). The bar NUMBER is what moves the range now, tap to start
  and hold to end, and the gaps between notes swallow a tap on purpose.
- **The tuner is the note check opened on a tuning note** (#32): "Tune your
  horn" under the Trainer's instrument picker. `Instrument.tuningNotes` says
  what each horn reads for concert F and concert Bb, open note first, because
  the main slide is set by an open note. `NoteCheck.Purpose.tuning` halves the
  in tune band to 10 cents and says which way the slide goes: sharp comes OUT.
  `NoteCheckView` borrows its "Hear it" player from whoever opened it
  (`ReferenceTone`), the chart's `PartPlayer` or the Trainer's `TonePlayer`,
  and never makes one. iOS only.
- **The listener only passes on a note that is being HELD** (`HeldPitch`,
  #34): three readings on one note, none dying away, and a silence floor of
  0.010. A new mail chime has a steadier pitch than a student; what marks it
  is that it was struck. "Dying" is under half while a sound is being
  decided and under a quarter once it is held, because a real attack and
  real air both sag. The numbers came off two real sessions and 20 real
  alert sounds, and `ios/README.md` says what still gets through. Do not
  move any of them without measuring both the chimes and the horn first.
- **The instrument is on every screen** (`InstrumentChip`, #36): pinned over
  each tab by `PageScaffold` and in the headers of the chart and the check
  screen. A new screen that depends on the instrument gets the chip. The
  check screen is re-aimed through its `retarget` closure when it changes.
- **The check screen fits the phone by measuring itself** (`ViewThatFits`,
  #35), full, then tight, then scrolling. Add a line of text to it and look
  at it in the simulator with both tuning notes and `-checkHeight 600`.
- **Run `bash ios/scripts/quiet-simulator.sh` before a test run or a
  simulator launch.** It turns the simulator's indexing off. One simulator,
  the iPhone 17; do not boot a second.
- **Holding a note opens the note check** (`NoteCheckView`, `NoteCheck`,
  `PitchListener`). It compares the microphone against the SOUNDING pitch for
  the selected instrument, a fifth under written on an F horn, never against
  `Note.frequency`: the Trainer and the scales play written pitch and a real
  horn does not. The audio session is `.playAndRecord` only while that sheet is open
  (`AudioSessionController.Mode`), and `.playback` with no options otherwise,
  which the metronome on a locked screen depends on.
- **`Pitch` (YIN) lives in the app now**, in `Audio/Pitch.swift`, and the tests
  use that one. It was calibrated before it was trusted; calibrate again
  before widening its range or changing its thresholds. The floor is 50 Hz
  since the euphonium (#25), measured down to its pedal Bb with the
  fundamental filtered out, and the scope is cut from a buffer twice as long
  as the one the pitch is measured on (`PitchListener.scopeWindow`), because
  six cycles of a low E do not fit in one.
- **"Hear it" on the note check holds the tone's filter open to 700 Hz**
  (`NoteCheck.referenceBrightnessFloor`). The tone's filter follows the note,
  and a sounding pitch an octave under the staff left nothing a phone speaker
  can make. Only the note check passes a floor; every other sound renders the
  samples it always did, and a test says so.
- **Suspect bars are shown and played, never hidden and never "fixed".** The
  screen says to trust the page.
- **Charts are copied to Application Support/Charts** and are the user's files.
  Sam's charts still never go in git and never go in a build.
- **The app ships ONE chart, and it is ours** (#28): `Resources/Sample Chart -
  Band Room March.pdf`, sixteen bars written for this app, engraved from
  `ios/scripts/sample-chart.musicxml`. `ChartLibrary.withSample()` copies it
  in once per install (`mello-sample-chart-seeded`), so removing it sticks.
  It is what a new install, a reviewer and the App Store screenshots open.
  Nothing else may go in the bundle as music: the App Store record declares
  no third party content. `SampleChartTests` reads it back note for note.
- **A beam is read as the shape it is** (#29). A slab's thickness is the height
  of its end and its line is followed along the slope; a path wider than 15
  half-spaces is a beam only if it joins two stems that carry notes. Raising
  the width ceiling instead lets a multi-measure rest's H-bar in.
- **One `PartPlayer`, owned by the charts card, never one per chart.** Its node
  stays attached to the shared engine for good. Detaching it from the running
  engine broke every player after it, and only the test that records the real
  engine's output saw that (`PartPlayerTests`). Run that suite after touching
  the player.
- **Version 2.0 build 4 went to App Review on 2026-10-11** (#7), release type
  MANUAL. The submit steps and what went wrong on the way are in
  `ios/README.md` under "Submitting to the App Store". The App Store
  screenshots show the sample chart; retake them the same way if the chart or
  the note check screen changes.
- **The note check has heard a real horn, once.** On 2026-10-11 Ryan held a
  note in the sample chart on his iPhone, played two notes, and it called
  both (#22). On 2026-10-13 he tuned a trumpet with the tuner, 27 notes
  confirmed (#32). Still not reported from a phone: "Hear it" through the speaker
  while the session records, and playback after the sheet closes. There is no
  stall watchdog on `PartPlayer`, so a part playing through a screen lock is
  untested.
- Preferences: `mello-part-tempo` (40 to 220, default 100) and
  `mello-part-count-in`. Debug launch args: `-openChart <path>`, `-partFrom <bar>`,
  `-autoPlayPart YES`, `-tapNote <n>`, `-checkNote <n>`, `-listenFake <Hz>`,
  `-tune YES` with `-tuneNote <n>` for the tuner, and `-checkHeight <points>`.

### Measuring the score reader against a real chart

`ios/Mellophone/Import/` needs nothing from the app but `Log` and `NoteData`, so
copy those files plus a `Log` stub into a scratch directory and build a
throwaway `swiftc` binary against a real PDF. That cycle is 45 seconds against 5
to 10 minutes for `xcodebuild test`, and every bug in the reader so far (the
subpath split, the H-bar, the MuseScore segments, the upside down staff) was
found by reading numbers off Sam's charts rather than by a unit test. Render a
crop of the page with `CGContext.drawPDFPage` and LOOK at it before believing a
reading. Sam's charts are copyrighted and never go in git.

### Divergences from the web version

Deliberate, and listed in `ios/README.md` with reasons. The notable one: the drill's text field becomes a tap grid, because typing "Bb4" on a phone keyboard while holding a horn is the wrong input for the situation.
