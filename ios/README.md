# Honk It Up!, iOS

The native app, shipping as **Honk It Up!** (`INFOPLIST_KEY_CFBundleDisplayName`).
The web version in this repo's `index.html` carries the same name since #12, is
the functional specification, and stays live as the fallback for anyone on
Android or a Chromebook.

Tracked as issue #2, built in phases: #3 scaffold and metronome, #4 note model
and trainer, #5 scales and drill, #6 timer and log, #7 ship.

## Why this is not a web view

Issue #2 lays out the full argument. The short version is that a `WKWebView`
wrapper around `index.html` would be rejected under App Store Review Guideline
4.2, and it would also be a worse instrument:

- A metronome driven by `setInterval` drifts, because JavaScript timers schedule
  the *sound*. This app schedules against the audio clock instead, so the
  scheduler's jitter is not the click's jitter.
- Practising means the phone is face down or in a pocket. That needs the `audio`
  background mode and a real `AVAudioSession`; a web view gets suspended.
- The click has to sound with the ringer switch off.
- A downbeat you can feel is useful when you are playing loudly.

## Collect nothing

No accounts, no analytics, no crash reporting SDK, no ads, and no network code
at all. There is no `URLSession` in the target. The practice log lives in
`UserDefaults` on the device and there is no backend to send it to. The App
Store privacy label reads "Data Not Collected".

This is not an aspiration, it is a constraint: the people who will use this are
likely to include minors. If a future feature seems to need a server, that is a
decision to take back to issue #2, not to implement.

**The microphone** (#22) is the one sensor the app uses, and it does not change
any of the above. It is on while the note check screen is open and at no other
time: not in the background, not during playback, not on any other screen. The
tuner (#32) is that screen, opened from the Trainer, and not a second one. Each
tenth of a second of audio is measured, reduced to a pitch and a 240 point
picture, and overwritten by the next. There is no file, no buffer longer than
a tenth of a second and no code path that could send it anywhere, because there is no network
code. Apple's definition of "collected" is data that leaves the device, so the
label still reads "Data Not Collected". The usage string is in `project.yml`
and says this in a sentence a parent would accept.

## Building

`xcodegen` is required (`brew install xcodegen`).

```sh
cd ios
xcodegen generate                   # project.yml -> Mellophone.xcodeproj
open Mellophone.xcodeproj
```

Command line, simulator:

```sh
xcodebuild -project Mellophone.xcodeproj -scheme Mellophone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Tests:

```sh
xcodebuild -project Mellophone.xcodeproj -scheme Mellophone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData test
```

Before either, on a build Mac that has anything else to do:

```sh
bash scripts/quiet-simulator.sh     # boots the test simulator with indexing off
```

A freshly booted simulator runs Spotlight's indexers and the media analysis
services behind them, and with the suite running beside them that was enough
to nearly stop the machine. The script disables the four services inside the
simulator and is safe to run every time. It exits 1, naming the service, if
any of the four is not listed as disabled afterwards. Its first version
counted every line that named a service, enabled ones included, and could
not fail (#37).

### `project.yml` is the source of truth

`Mellophone.xcodeproj` is generated. Anything hand-edited in it is silently
reverted by the next `xcodegen generate`, and the drift is invisible until an
upload fails. That applies especially to `CURRENT_PROJECT_VERSION`: bump it in
`project.yml`.

The project is committed anyway, so a clone can be opened in Xcode without
running XcodeGen first. Same convention as the sibling repo `Ryan4n6/TPS-iOS`.

### Settings that are load-bearing

These came out of real App Store failures in `TPS-iOS`. Each one is commented in
`project.yml` with the outage it prevents; the short list:

| Setting | What breaks without it |
|---|---|
| `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` | Every build lands as "Missing Compliance", invisible to TestFlight testers and un-addable to a beta group |
| `TARGETED_DEVICE_FAMILY: 1` | Upload validation rejects the build for not declaring all four iPad multitasking orientations |
| `CODE_SIGNING_ALLOWED: YES` | The archive is unsigned, so any entitlements file is ignored and its entitlements silently do not ship |
| `UIBackgroundModes: [audio]` via the partial `Mellophone/Info.plist` | iOS suspends the engine when the screen locks, which is most of the time this app is in use. Note it CANNOT be done with `INFOPLIST_KEY_UIBackgroundModes`: the key is an array, that build setting is accepted silently, and the key never reaches the built plist. Verify it in the BUILT app, not the settings |

## Submitting to the App Store

The archive-and-upload half is `scripts/testflight.sh`. The submit half is not, and it
has a trap in it.

**Field-by-field preflight lies. A dry-run review submission does not.** Reading the
version record attribute by attribute reported everything filled in, and Apple still
refused the submission on four counts. The one that a field read can never catch is
pricing: with no price schedule the app is simply not submittable, and there is no
empty field anywhere to notice, because the resource does not exist until you create it.

So the only honest preflight is to ask Apple:

```sh
# create a submission, try to add the version, read the errors, then clean up
python3 scripts/asc.py post /v1/reviewSubmissions \
  '{"data":{"type":"reviewSubmissions","attributes":{"platform":"IOS"},
    "relationships":{"app":{"data":{"type":"apps","id":"6802899812"}}}}}'
python3 scripts/asc.py post /v1/reviewSubmissionItems \
  '{"data":{"type":"reviewSubmissionItems","relationships":{
    "reviewSubmission":{"data":{"type":"reviewSubmissions","id":"<SID>"}},
    "appStoreVersion":{"data":{"type":"appStoreVersions","id":"<VID>"}}}}}'
```

A 409 on the second call carries `meta.associatedErrors`, which names every blocker at
once. That single call found all four of these, on an app record that every other check
called complete:

| blocker | fix |
| --- | --- |
| `contentRightsDeclaration` missing | `PATCH /v1/apps/{id}` -> `DOES_NOT_USE_THIRD_PARTY_CONTENT` |
| `copyright` missing | `PATCH /v1/appStoreVersions/{id}` -> `2026 Massfeller LLC` |
| `APP_PRICING_REQUIRED` | `POST /v1/appPriceSchedules`, free price point, base territory USA |
| `APP_DATA_USAGES_REQUIRED` | web UI only, see below |

**`reviewSubmissions` has no DELETE.** Allowed operations are CREATE, GET, UPDATE. A
cleanup `DELETE` fails with 403 and, if its return value is not checked, leaves an empty
draft submission on the account every time the dry run is used. `PATCH {canceled: true}`
does not work either: an unsubmitted draft returns 409. The only way to remove one is
App Store Connect -> the version page -> Draft Submissions -> Delete Submission.

**App Privacy cannot be set from the API at all.** `/v1/appDataUsages`,
`/v1/appDataUsageCategories`, `/v1/appDataUsageDataProtections` and both spellings of the
publish-state relationship all return `PATH_ERROR`, meaning the path does not exist rather
than that the record is empty. It is App Store Connect -> App Privacy -> Get Started ->
"No, we do not collect data from this app" -> **Publish**. Saving is not enough, the
blocker asks for *published* answers. Our answer is the true one and is asserted by the
build: `testflight.sh` fails the upload if any networking symbol appears in the binary.

Submitting, once the dry run comes back clean, is `PATCH /v1/reviewSubmissions/{id}`
with `{"submitted": true}`. Release type is MANUAL on purpose, so approval means ready
and a human still presses the button.

### Getting a build to a TestFlight tester

`scripts/testflight.sh` only uploads. A build nobody was given is a build
nobody sees: the one group, "Preview", is internal and does NOT get every
build on its own (`hasAccessToAllBuilds` is false). After the upload reports
`VALID`:

```sh
# give the group the build
python3 scripts/asc.py post /v1/builds/<BUILD>/relationships/betaGroups \
  '{"data":[{"type":"betaGroups","id":"<GROUP>"}]}'
# what the tester reads under "What to Test"
python3 scripts/asc.py patch /v1/betaBuildLocalizations/<LOC> \
  '{"data":{"type":"betaBuildLocalizations","id":"<LOC>","attributes":{"whatsNew":"..."}}}'
# send, or send again, the invitation email
python3 scripts/asc.py post /v1/betaTesterInvitations \
  '{"data":{"type":"betaTesterInvitations","relationships":{
    "betaTester":{"data":{"type":"betaTesters","id":"<TESTER>"}},
    "app":{"data":{"type":"apps","id":"6802899812"}}}}}'
```

The ids come from `/v1/betaGroups?filter[app]=6802899812`,
`/v1/betaTesters?filter[apps]=6802899812` and
`/v1/builds/<BUILD>/betaBuildLocalizations`. The first call answers with an
empty body when it works; read `/v1/betaGroups/<GROUP>/builds` back to be
sure. An internal group needs no beta review. A build uploaded while a
version is waiting for App Review does not touch the submission: the build
under review stays the one that was attached to it.

Build 5 went to the Preview group this way on 2026-10-13, with the tuner in
it.
Build 6 followed on 2026-10-19 with the card view and printed lyre cards
(#43), the printed tempos (#41), the reader fixes (#39) and the tuner fix
(#37).

### What the 2.0 submission added to this (October 2026)

**Do the dry run on the submission you mean to send.** Create ONE review submission and
add the version to it. A 201 on the item is the clean preflight, and that same submission
is then the one that gets `{"submitted": true}`. Nothing is left behind to delete in the
web UI, which is where three empty drafts came from the first time.

**The version record is renamed, not replaced.** 1.1 was never released, so its record
became 2.0 with `PATCH /v1/appStoreVersions/{id}` and `{"versionString": "2.0"}`.
`MARKETING_VERSION` in `project.yml` has to say the same thing before the upload.

**Screenshots.**

- A set holds ten. Replacing six with six means upload four, wait for `COMPLETE`, delete
  the old six, upload the last two. Deleting first leaves the listing with none if an
  upload then fails.
- `xcrun simctl io <device> screenshot` writes a PNG with an alpha channel, and Apple
  fails any alpha during processing, after the upload has reported success. Flatten onto
  black first, and poll `assetDeliveryState`.
- The generated launch screen is white. On a slow machine a capture taken on a fixed
  delay is a white frame with a status bar on it. Measure the capture's brightness and
  wait for a dark one, then pull every image back from `imageAsset.templateUrl` and look
  at what Apple is actually holding.
- The shots are taken from a debug build with the launch arguments in `CLAUDE.md`
  (`-openChart`, `-tapNote`, `-checkNote`, `-listenFake`), on a simulator with
  `simctl status_bar override`. They show the sample chart, because that is the only
  chart we own.

**A simulator that has been up for days can wedge the whole build.** `simctl` calls
hang, `xcodebuild test` sits at its first step, and its media analysis daemon holds a
core. `xcrun simctl shutdown all`, `xcrun simctl erase "iPhone 17"`, then
`build-for-testing` and `test-without-building` as two steps, got a full run through
on a machine that had stalled five in a row.

**Stacked pull requests after a fast-forward.** Pushing `main` forward marks only the
PR based on `main` as merged. For each of the others, push its BASE branch forward to
`main` as well, lowest first, and GitHub records it as merged instead of leaving it
open with nothing to merge.

## How the metronome works

`Audio/BeatSchedule.swift` holds the arithmetic and nothing else, so it can be
tested without a device, a session, or a speaker.

The failure being avoided is an accumulating cursor:

```
next = previous + period      // every rounding error is inherited, forever
```

At 44,100 Hz and 137 BPM a beat is 19,313.868… samples. Truncating loses about
0.87 samples per beat. `MellophoneTests/BeatScheduleTests` measures this: after
50,000 beats the accumulating version is off by more than nine tenths of a
second. Every beat is instead computed from a fixed anchor:

```
beat(i) = anchor + round(i * period)
```

which is never more than half a sample from ideal, about 10 µs at 48 kHz, at any
beat count.

`Audio/Metronome.swift` wraps that in an `AVAudioEngine`. The shape is:

- A `DispatchSourceTimer` wakes roughly every 40 ms and keeps 250 ms of clicks
  queued on an `AVAudioPlayerNode`, each with an explicit `AVAudioTime` sample
  position. **The scheduler is allowed to be late; the schedule is not.**
- The beat dots and the haptic are driven from the same audio clock, not from an
  independent UI timer, so the display cannot drift against the sound.
- Changing tempo re-anchors and flushes the queued buffers, carrying the current
  beat-in-measure across so a nudge mid-bar does not move the downbeat.
- Interruptions (a phone call), route loss (headphones pulled), and engine
  configuration changes (a Bluetooth route change moving the sample rate) each
  have an explicit handler.

`DriftReadout` in `Views/MetronomeView.swift` is a `#if DEBUG` panel that shows
beats sounded, audio-clock and wall-clock elapsed, their skew, and the worst
schedule error so far. It exists so the timing claim can be answered with a
measurement taken on the device instead of an assertion about the design.

## The note data is generated, not transcribed

`Mellophone/Model/NoteData.swift` is produced from `index.html` by
`scripts/sync-note-data.py`. Do not edit it by hand.

```sh
python3 ios/scripts/sync-note-data.py            # regenerate
python3 ios/scripts/sync-note-data.py --check    # fail if it drifted
```

Issue #2 asks for the tables to be "lifted, not retyped from memory". They are
not retyped at all. One wrong frequency or fingering is close to invisible in
review, being a single digit in a table of 37 rows, and completely wrong in the
hand, so the fix is to never transcribe it by hand in the first place. Run
`--check` before shipping to prove the Swift still matches the page.

## The fingering chart is derived, not remembered

Every three-valve brass instrument shares one chart relative to its own written
notes. The open notes are C4, G4, C5, E5, G5, C6, and everything else is the
nearest partial above it lowered by valves: 2 is one semitone, 1 is two, 1+2 is
three, 2+3 is four, 1+3 is five, 1+2+3 is six. Three valves reach six and no
further.

Seven rows disagreed with that once (#9). F#3, Gb3, G3 and Ab3 carried a
neighbouring note's fingering; C#4 and Db4 used the combination that is only
correct an octave higher; and F3 was in the table at all, despite needing seven
semitones. Published charts confirm all of it, including the subtlety that C# is
`1+2+3` low and `1+2` an octave up because they come off different partials.

That mattered more than a normal data bug: the drill prints the fingering as
CORRECTIVE feedback, so a wrong value actively teaches the wrong thing, and the
Same Fingering card groups by exact string equality on the fingering.

Two guards, because the table is fully derivable and should never again be a
list of remembered facts:

- `scripts/sync-note-data.py` derives the chart and REFUSES TO GENERATE if
  `index.html` disagrees, naming each offending row.
- `MellophoneTests/FingeringChartTests` asserts the same thing about the shipped
  data, pins the six rows that were wrong by name, and checks the table against a
  published trumpet chart.

## Range

Written F#3 to C6 is the instrument's span, and it is what is expected of a
**drum corps lead player**. Players on the range:

> "F# below the staff is the lowest the mello can play."
>
> "the usable range stops around a C above the staff... Even then, above the
> staff can be iffy."

The treble staff tops out at F5, so "above the staff" is G5 upward. The chart
covers everything, but the practice range DEFAULTS to **C4 to G5**, which is
where a high school player actually lives. Widening it is one tap away.

## Four instruments, two differences

`Model/Instrument.swift`. Most of the app was already instrument-agnostic
without anyone intending it: the staff, the reading drill, the metronome and the
timer all depend on written pitch. Only two things differ per instrument, plus
what an imported chart sounds like (see "A chart sounds like the horn" below).

**Fingerings.** A mellophone and a trumpet sit in the same place in the harmonic
series relative to their written notes, so they share a chart. A French horn's F
side sits an OCTAVE LOWER, which packs more partials into the staff and gives it
many more open notes:

| | open written notes |
|---|---|
| Mellophone, trumpet, euphonium (treble clef) | C4, G4, C5, E5, G5, C6 |
| French horn, F side | G3, C4, E4, G4, C5, D5, E5, G5, C6 |

Written E4 is open on a horn and `1+2` on the other two. Written D5 is open on a
horn and `1`.

**Concert keys.** Written F is concert Bb on an F instrument and concert Eb on a
Bb trumpet. The written half of a scale's name is the fact; the concert half is
computed from it. Lip slurs and long tones are exercises rather than keys and
pass through untouched.

Fingerings are DERIVED from each instrument's partials rather than stored, for
the reason in the section above: a table of remembered facts is the wrong shape
for something this mechanical. `InstrumentTests` checks the derivation against
the published trumpet chart, against the published Single F Horn chart (Stewart
Schlazer), and against the stored mellophone table, so the three cannot drift
apart.

**The euphonium is the treble clef one (#25).** A euphonium or marching baritone
part comes in two forms. "Baritone T.C." is read exactly like a trumpet part,
same valves note for note, and sounds a major ninth under the page: that is the
`euphonium` here, and it costs one row, the trumpet's partials with a
transposition of 14. A bass clef part is the same valves under different note
names on a different staff at concert pitch, and the app has no bass clef to
draw it or to read it out of a PDF, so it is not offered and the picker's
caveat says so. The fingerings are pinned against the Mouthpiece Express
*Euphonium, Baritone, Valve Trombone Basic Fingering Chart*, rendered and read
on 2026-10-10. That chart is printed in bass clef at concert pitch, E2 to Bb4,
so the test reads each of its 31 notes a major ninth up and asks for the same
fingering; all 31 agree, and they cover every note in the app's table. A
control reads the chart an octave up instead and requires most of it to
disagree. The four valve line in the caveat (4 for 1+3, 2+4 for 1+2+3) is how
the fourth valve is built, a perfect fourth, and is NOT pinned to a chart.

So is the Same Fingering card's grouping: `Note.sameFingering(on:)` lives in
`Model/Instrument.swift` next to the derivation it depends on, and the Trainer
calls it rather than carrying its own copy. `Note` itself knows nothing about
instruments. It briefly had a `sameFingering` that filtered the stored mellophone
column, which was unused, instrument-blind, and covered by a test that no longer
touched the card it was named after (#13).

Known gaps, stated in the app rather than left to be discovered: the horn's Bb
side is different, and the horn plays lower than this chart goes because the
note table was built around the mellophone's floor of F#3.

## Historical: this app was mellophone and trumpet only

Mellophone and trumpet share the chart above, so a trumpet player can read their
own part against it. Their scale LABELS differ though: written F is concert Bb on
an F instrument and concert Eb on trumpet (#10).

**French horn does not share it.** Its F side sits an octave lower in the
harmonic series, so it has far more open notes in the staff: G3, C4, E4, G4, C5,
D5, E5, G5, C6 are all open on horn. Written E4 is open on horn and `1+2` here.
A horn player can use the staff reading, the drill, the scales and the metronome,
but not the fingering chart, the Same Fingering card, or the valve diagram.

## The staff

`Views/StaffView.swift` draws in the same coordinate space as the web version's
SVG, five lines at y = 60, 80, 100, 120, 140 (F5 D5 B4 G4 E4), with two
differences.

**The conversion is `staffPosition + 20`, not `staffPos * 0.5 + 30`.** The web
version halves the scale, so no line note lands on its line and the whole range
collapses into the top half of the staff. That is issue #8, a real bug in the
live web app that this port found. It is the one place the native app is
deliberately not faithful to the spec, because a note-reading drill that draws
the wrong note teaches the wrong thing. `StaffGeometryTests` pins the five line
notes to their lines and explicitly asserts the web formula is NOT in use, so
nobody restores fidelity by accident.

**The canvas is 230 tall and there are three ledger lines below**, not two. F3
is the bottom of the written range and sits at y = 200, which the web version's
200-tall space could never have shown.

### Nothing on the staff depends on a font

The clef and both accidentals are vector paths.

- **The treble clef has to be.** No font shipped with iOS covers U+1D11E, the
  MUSICAL SYMBOL G CLEF. Checked against all 264 font files in the iOS 26.5
  runtime: zero hits. It would render as an empty box on a phone. Desktop
  browsers have a fallback that covers it, which is why the web version got away
  with setting it as text for as long as it did.

  It is **filled artwork, not a stroke** (#14). It began as a hand-drawn
  centreline stroked at a constant width, which reads as a squiggle: a real
  clef's weight swells and tapers and a constant-width stroke cannot. Both
  products now draw the same paths, from `scripts/treble-clef.svg` via
  `scripts/make-treble-clef.py`, which writes `Views/TrebleClef.swift` and takes
  `--check` to fail if the two have drifted. Placement is measured, not
  eyeballed: the source glyph is 276.164 square with its spiral at (148, 172),
  scaled to 135 units (6.75 staff spaces) and translated so that spiral lands on
  the G4 line at y = 120. A clef whose spiral is not on the G line is decoration.
- **The sharp and flat did not have to be, and are anyway.** Both are in the
  Basic Multilingual Plane and iOS does carry them, but not in the same faces:
  25 fonts have U+266F and only 13 have U+266D. Times New Roman is a concrete
  example with the sharp and without the flat. Asking for a serif glyph and
  letting CoreText fall back risks drawing the two accidentals in two different
  typefaces on the same staff.

## Scales play as one buffer

The web version fires a `setTimeout` per note, so every note inherits the
timer's jitter and the run wobbles. `Audio/ScalePlayer.swift` renders the WHOLE
SCALE into one buffer with each note at an exact sample offset and hands it over
in a single call. The spacing is then a property of the buffer rather than of
anything that has to wake up on time, so it cannot wobble.

Notes are summed rather than overwritten where they overlap, because at the
fastest speed a note's release is still sounding when the next begins and
overwriting would chop it off mid-decay. The buffer is scaled back if the sum
pushes past full scale; clipping a scale run is far more audible than it being
slightly quieter.

## Charts play a few bars at a time

A student can bring in the PDF of their own part (Scales tab, "Your Charts"),
and hear it. The reader that turns the PDF into a `Score` is described in
`docs/superpowers/specs/2026-09-06-score-import-design.md`. This section is
about what happens after it.

**`Audio/PartTimeline.swift` is arithmetic and nothing else.** A score, one line
of it, a range of bars and a tempo go in; entries in seconds come out. No audio
and no clock, so "which note is sounding at second 41.3 of bars 12 to 20 on the
bottom line at 84" is a unit test (`PartTimelineTests`).

**`Audio/PartPlayer.swift` puts buffers end to end.** A scale is ten seconds and
renders as one buffer. A four page chart at a slow tempo is ten minutes, over a
hundred megabytes that way, so the timeline is cut into chunks of at least three
seconds ON BAR LINES and each is rendered while the ones before it sound. They
are queued with `at: nil`, two deep, so each buffer's length places the next.
That is the metronome's rule and it is here for the metronome's reason: nothing
is scheduled against the player's clock, so a stalled clock cannot stop the
music being queued.

Three things in there that look like they could be simpler and cannot:

- **Chunk boundaries are rounded from their own position**, never summed from
  the lengths before them. That is `BeatSchedule`'s rule. A sum of rounded bar
  lengths wanders, and over 256 bars the highlight would slide off the sound.
- **`ToneSequence.render` takes an exact frame count**, and returns silence for
  a chunk with no notes in it. Returning nil for "no events" was right for a
  scale and would drop every bar of rest from a part, pulling the rest of it
  early.
- **`stop()` waits for a render in flight** before flushing the player. Without
  the wait the render can finish after the flush and leave its buffer queued on
  a stopped player, where it plays in front of the next count-in.

**The mixer and the wavetable build use Accelerate**, and the reason is the
debug build, which is what `scripts/run-device.sh` installs. Pressing Play on a
real chart in the simulator took about 1.5 s to ready the first bars. Two causes,
measured separately: `ToneSequence` cleared, summed, peak-scanned and scaled with
plain loops (about 0.9 s once those were on vDSP), and `SawtoothTable` built each
table with 2048 x harmonics calls to `sin()`, 143 ms a table, several tables
needed cold (about 0.35 s once that was on vForce). The player logs both halves
of the wait on every Play in debug, `engine N ms, first bars N ms`, because a
cold engine and a slow render look the same from outside.

**A tempo number counts the pulse, not the bottom number.** `Pulse` gives a
quarter in 4/4, a half in 2/2 and a DOTTED quarter in 6/8, because a 6/8 march
marked 120 is felt in two. The screen says what the number counts. Since #41
the number starts at the page's tempo when the chart prints one; see "The
page's tempo" below.

**A chart opens at the first bar with a note in it, and a rest is counted out
loud.** Both came from the first listen on a phone (2026-10-10). Sam's opener
sits out fifteen bars, so starting at bar 1 was 36 seconds of silence after the
count-in, on a still screen, and read as the app having broken. Now the range
starts where the player comes in and a gold line says so; "Whole part" goes
back to bar 1. Through a whole bar of rest the pinned card shows the beat, 1 to
4, with "rest, bar 4 of 15" under it. The beat comes from
`PartTimeline.beat(at:)` off the audio clock and is counted from the bar line,
so a short bar does not put every later count out of step. A time that lands
exactly on a beat can divide out to 1.9999999999999998 (72 bpm, bar 2), which
is what the small nudge in that function is for and why its test runs at 72.

**A part is phrases, not a row of separate notes** (2026-10-10, from the same
first listen: "extremely choppy and gated from note to note"). The scale
renderer gives every note 100 ms of fade to silence and 40 ms of fade back in,
and the part player clipped each note short on top of that. At 120 an eighth
note is 250 ms, so more than half of every one was fade. Measured on the
authored fixture, the sound was below half its held level for **100 ms** at
every join. Now it is **10 to 14 ms**, which is a tongue and not a gate.

- `PartTimeline.phrased` marks each note `tonguedIn` and `carriesOn`: two notes
  are one phrase when the second starts where the first ends, and a rest or the
  end of the range is a breath. It is decided there and carried on the note
  because a part is rendered a few bars at a time and the renderer cannot see
  the buffer before its own.
- `TonePlayer.render` takes an `Articulation`. A note that carries on is held
  for all of its written length and closes in its last 20 ms; a note tongued in
  rises in 10 ms to a small bump and opens its filter less far than the first
  note after a breath. `Articulation.separate` is the default and is the old
  path untouched, so scales and tapped notes render what they always did.
- **No slide between notes.** A valved horn does not glide; the pitch is on the
  next note within a few milliseconds. What it does do is ARRIVE: each note
  opens a few cents under (18 after a breath, 6 when tongued) and is home
  inside 80 ms. After that it is exactly on pitch. There is no drift and no
  vibrato on purpose, because a student tunes their ear to this.
- **Slurs are not read**, so every note in a phrase is tongued.

**A room** (`PartRoom`: Dry, Room, Hall; `mello-part-room`, default Room).
`AVAudioUnitReverb` between the part's player and the mixer, changed live from
the Sound chips. Dry BYPASSES the unit, so the test that compares the engine's
output with the rendered samples still holds to 1%. Two things were learned
from the real engine, both now pinned by `PartPlayerTests`:

- The reverb will not initialise with a mono OUTPUT (error -10868). Mono in,
  stereo out.
- **The main mixer must exist before the engine starts.** `AudioEngineHost`
  used to start the engine and let the mixer be made on first use, which works
  for a player wired straight into it. A chain wired into a mixer made late
  connects without complaint and then raises "player started when in a
  disconnected state" on play. Reproduced on a bare engine outside the app:
  every order of connecting failed, and only making the mixer first, or
  restarting the engine, fixed it.

**Tap a note to hear it** (2026-10-10, from Ryan trying to play a part off the
phone: there was no way to spot check one pitch). A tap sounds that note for
1.2 s and leaves it on the pinned staff with its valves, outlined in the list,
until the passage is played or its start is moved. It goes through the part's
own player (`PartPlayer.sound`), so it comes out of the same room, and a tap in
the middle of a run stops the run instead of sounding over it. The price is the
old gesture: a tap anywhere on a bar used to move the start of the range, and
now only the bar NUMBER does, drawn as a key so it reads as one. The space
between two notes swallows a tap on purpose. A range that moves because a thumb
missed a note by four points is worse than a tap that does nothing.

**Hold a note to check yourself against it** (#22, 2026-10-10, the second half
of the same request). A sheet with the note on the staff and its valves, a
button that plays it, and the microphone listening to the horn: the screen
names what it hears, says how many cents out it is and which way, and ticks
the note once it has been HELD in tune for about 0.6 s: two readings while the
listener decides the sound is a note at all (#34), and four more in tune.

- **Transposition is the whole risk.** Everywhere else a written C5 is 523 Hz,
  because nothing else ever had to agree with a real instrument. A mellophone
  playing C5 puts concert F4, 349 Hz, into the microphone. `NoteCheck` compares
  against the SOUNDING pitch (`Instrument.transpositionSemitones`), and "Hear
  it" on that screen plays the sounding pitch too, since that is the sound to
  match, and says under the button which concert note that is. Since #24 the
  note tapped in the list and the part itself play that same pitch, through
  the one function `Instrument.sounding`. `NoteCheckTests` pins this against
  published frequencies and shows a written 523 Hz being judged a wrong note.
- **A wrong note is named, and the valves are judged separately.** Past half a
  semitone the screen says which written note it was. If that note takes the
  same fingering it says "Right valves, wrong note", which is the brass miss a
  student cannot find by looking at their fingers.
- **In tune is 20 cents either way**, not 5. The phone knows nothing about the
  tuning slide and this is a student checking they have the right note.
- **The detector is the one from the tests.** `Pitch` (YIN) moved from
  `ScalePitchTests` into the app, so the detector that ships is the one that
  was calibrated. It gained a `doubt` limit, strict for a microphone (0.25) and
  loose for the tests (0.5), because most of what a microphone hears is not a
  note. Its range was extended down to 70 Hz and calibrated there first.
- **The session changes category for the life of the sheet.**
  `AudioSessionController` has a `Mode`: `.playback` as always, `.listening`
  as `.playAndRecord` with `defaultToSpeaker` and `allowBluetoothA2DP`. Players
  call `activate()` on every sound and it sets up for the CURRENT mode, so the
  reference tone does not put the session back and switch the microphone off.
  Leaving sets `.playback` with no options again at once. The metronome is
  stopped when the sheet opens: a click in the room is a pitch to a microphone.
- **`PitchListener` has its own engine, input only.** It never asks the shared
  engine for its input node, which would mean rebuilding that engine under the
  metronome.
- **It goes deaf while the app plays** (`cover(for:)`). The speaker is two
  centimetres from the microphone, and the reference tone is the target pitch.
  A reading already in flight when the tone starts is dropped as well; a test
  caught one sitting on the screen for the whole tone.
- **The scope is smoothed, and that was decided by looking.** Drawn raw through
  a real microphone the wave was a scribble with thirty peaks over a sine with
  six. It is averaged over half its own period, twice, which leaves close to
  the fundamental alone, and drawn across six cycles OF THE TARGET from the
  point its fundamental rises through zero. On pitch it lies on the gold line;
  flat it is stretched and falls behind; sharp it runs ahead.

What was checked and how. `NoteCheckTests` and `PitchAnalysisTests` run the
shipping detector on the app's own rendered tone at the sounding pitch of every
note on every instrument (worst error 0.015 cents), with a control that a
semitone out is caught for every note, and on silence and white noise. The
verdict and wording tests feed numbers in. `ListeningSessionTests` switches the
simulator's real session there and back, and drives the listener with a debug
stand-in for the microphone (`-listenFake <Hz>`), which exercises everything
after the microphone and not the microphone. Beyond the tests, the real input
path was run once in the simulator, which uses the Mac's microphone: a 277.18
Hz tone played from the Mac's speakers was heard as 277.2 Hz and confirmed, a
272 Hz tone as 33 cents flat, and the quiet room as nothing.

**The low end, for the euphonium (#25).** Its bottom note sounds E2, 82 Hz, a
fifth under anything the detector had been asked for, so three things were
measured before it was offered. The detector's floor moved from 70 to 50 Hz, so
the pedal Bb under the horn (58 Hz) is named and not met with an empty screen;
every semitone from there to G6 comes back within 3 cents at 44.1 and 48 kHz.
A phone's microphone hears almost nothing that low, so the same sweep was run
with everything under 300 Hz filtered off and the fundamental shown to be gone:
the notes are still named, because YIN measures how often the wave repeats and
overtones alone repeat at the fundamental. And the scope drew nothing for the
bottom three notes, because six cycles of a low E are longer than the 4096
samples the pitch is measured on; the listener now keeps 8192 for the picture
(`PitchListener.scopeWindow`) and still measures on the newest 4096. The
filter in that test is a guess at a phone and not a measurement of one.

The speaker has the same problem the other way round, and the plan for #25
missed it until a test failed. The app's tone is a sawtooth through a lowpass
that settles at one and a half times the note, so a low E keeps its second
harmonic 11 dB down and its fourth 30, and a phone's speaker makes very little
under about 300 Hz: "Hear it" would have played the right note where nobody
could hear it. Measured as the energy left above 300 Hz, the quietest reference
note sat 26.8 dB under the loudest on a euphonium and 20.1 dB on a mellophone
or a horn, which means this was already true of the bottom of the mellophone
in #22. The note check now holds that filter open to 700 Hz
(`NoteCheck.referenceBrightnessFloor`, `TonePlayer.render(brightnessFloor:)`),
which brings every horn inside 8.6 dB. Nothing else in the app passes a floor,
and a test holds `render` to the same samples as before when none is given.
This is a measurement of the signal. Nobody has listened to it on a phone.

Lowering the floor was also checked for what it costs in a noisy room, since a
lower floor gives the detector more wrong octaves to fall into. With white
noise or a low hum up to 5 dB under the note, 50 Hz and 70 Hz give the same
answers (252 right of 258 either way, the 6 misses being an octave down). They
part only when the noise is as loud as the note, where neither is usable.

**Heard on a phone, once.** On 2026-10-11 Ryan ran a debug build of `0e91848`
on his iPhone, held a note in the sample chart, and played two notes on a horn
he had not played before. The note check called both. That is one player, one
horn and one room, and it is the only time this has heard a brass instrument.

**Still not verified:** a student's unsteady note, a band room, a euphonium.
And on a phone: whether "Hear it" comes out of the speaker with the session set
to record, and whether playback is normal again after the sheet closes. Nobody
has reported either one yet.

**Sounded by ear** (`PartPlaybackTests`), the same way the scales are. The
fixture PDF goes through the real reader, the chunks are rendered and joined
exactly as the player queues them, and the YIN detector names the note at each
position the timeline claims one. A control plays bars 3 and 4 and listens for
bars 1 and 2, and has to hear all eight notes as wrong.

**And recorded off the real engine** (`PartPlayerTests`). One test taps the
engine's mixer while the real `PartPlayer` plays in real time, then checks the
ten second recording two ways. It is compared sample for sample with the
count-in and the chunks laid end to end, which has to explain it to within 1%,
and the YIN detector names every note against the note table. The first proves
the schedule and the second proves the notes; either alone can be fooled. This
is the test that notices a late chunk, a hole at a seam, or a player that says
it is playing and is silent. It was watched failing: with each scheduled click
shortened by 50 samples, 4.5 ms in all, the mismatch went from under 1% to 468%.

It has already earned its keep. `PartPlayer` used to detach its node in
`deinit`, so a player per opened chart would not pile nodes up on the shared
engine. Every state-only test passed. This one raised an AVFoundation exception:
taking a node off the RUNNING engine left the next player's node outside the
output chain. Hence one `PartPlayer`, owned by the charts card.

What the tests are NOT. The timeline and bar-list tests run on scores built by
hand, which proves the arithmetic and not the reading. Sam's real charts are in
no automated test, because they cannot be committed; they were opened and played
in the simulator and looked at. Nothing automated touches the file picker,
OneDrive, a locked screen or a speaker.

**Charts are copied into Application Support/Charts** (`Model/ChartLibrary`).
The file picker returns a security-scoped OneDrive address that does not survive
a relaunch, and a part gets opened daily for weeks, often with no signal. A
chart that turns out to be unreadable is removed again straight away. Nothing in
that folder shipped with the app.

**Not verified by listening on a phone yet.** Everything above is tests plus the
simulator, which shows the highlight following and logs what was scheduled, and
cannot tell you how it sounds on a speaker or what happens when the screen
locks mid-part. `PartPlayer` has no stall watchdog like the metronome's. It
stops itself on a route change and that is all.

Debug launch arguments, in the pattern of `-startScale`:

    xcrun simctl launch booted com.massfeller.mellophone \
      -startTab scales -openChart /path/to/chart.pdf -partFrom 16 -autoPlayPart YES

`-tapNote 6` taps the sixth note in the list, which is the only way to see a
tapped note in the simulator from a script. `-checkNote 6` holds it, which
opens the note check, and `-listenFake 277.18` makes that screen hear a steady
tone at that pitch in place of the microphone. Without `-listenFake` the
simulator listens through the Mac's own microphone, once it has been allowed:

    xcrun simctl privacy booted grant microphone com.massfeller.mellophone

## Tuning the horn (#32)

Sam asked to be able to tune his instrument from the app. "Tune your horn"
sits under the instrument picker on the Trainer tab and opens the note check
on a tuning note.

- **It is the note check, not a second screen.** The app's promise is that the
  microphone is on in exactly one place. `NoteCheckView` now takes a list of
  targets, one for a note held in a chart and two for a horn's tuning notes,
  and `PitchListener` still has one caller. What differs is carried by
  `NoteCheck.Purpose`.
- **The director says the concert pitch and the screen says the horn's note.**
  `Instrument.tuningNotes`:

  | Horn | Concert F | Concert Bb |
  |---|---|---|
  | Mellophone, French horn | written C5, open | written F4, valve 1 |
  | Trumpet, euphonium (treble clef) | written G4, open | written C5, open |

  The open C5 comes first on every horn, because the main slide is set by an
  open note: a note with a valve down is also tuned by that valve's slide.
- **Ten cents, not twenty.** The note check's question is "is this the right
  note" and it calls anything inside 20 cents right. A horn 15 cents out is the
  right note and needs its slide moved, so the tuner's band is 10 and the
  number of cents is on the screen the whole time. Not 5: the detector could
  support it, a student's held note cannot.
- **It says which way the slide goes.** Sharp is a horn that is too short, so
  the slide comes out; flat, it goes in. A test pins the two sentences so they
  cannot be swapped.
- **"Hear it" borrows a player** (`ReferenceTone`). The chart lends its
  `PartPlayer` and the Trainer its `TonePlayer`. A player is a node that stays
  on the shared engine for good, so one made per sheet would pile up.
- **The metronome is stopped on the way in**, as it is for the note check.

**Measured, before it was trusted.** The detector had only ever been asked for
"within 20 cents". Outside the suite, in a release build of `Pitch.swift` and
`PitchAnalysis.swift` on their own: every cent from 40 flat to 40 sharp, five
tones each with random overtone phases, at the four sounding pitches (F3
174.61, Bb3 233.08, F4 349.23, Bb4 466.16 Hz), at 44.1 and 48 kHz, clean, with
noise 26 dB down, and with noise and nothing under 300 Hz. 9,720 readings,
none without a pitch, worst error 0.09 cents. The suite repeats a cut of that
on every run (`testANoteAFewCentsOutIsReadToHalfACentAtEveryTuningPitch`, 272
tones, every fifth cent, worst 0.095 cents) and checks the verdict is the right
one each time.

**Hand-built input:** all of it. The tones are twelve steady overtones made in
the test, and the verdict and wording tests feed numbers straight in. They
prove the arithmetic and the detector's precision on a steady tone.

**It has tuned a real horn, once.** On 2026-10-13 Ryan tuned a trumpet with it
on his iPhone: concert Bb on the open C5 and concert F on the open G4. The
phone's own log has 27 notes confirmed in tune, between 9.8 cents low and 7.7
high, and the screen calling the G he fell onto while aiming at C5 by name.
What that session found wrong is the next section.

**Not verified:** a mellophone, which is the horn it was asked for. "Hear it"
was not pressed in that session, so the Trainer's `TonePlayer` sounding while
the session records has still not been heard on a phone, and the same button
through the chart's player is unreported too.

To look at it in the simulator without a horn:

    xcrun simctl launch booted com.massfeller.mellophone -tune YES -listenFake 353.3

`-tuneNote 2` opens it on the second tuning note.

## Only a held note is heard (#34)

The first time the tuner was used on a real horn it also reacted to the new
mail sound from a computer in the room. Two changes, both made from
measurements and both in `Audio/PitchAnalysis.swift`.

**What was measured.** The phone's `diagnostic.log` from that session, one
reading in ten: 234 readings with a pitch, 143 of them within a semitone of
the note being tuned. Every reading between level 0.005 and 0.010 (13 of
them) was at 58 to 61 Hz: the room's mains hum, shown as a note whenever
nobody was playing. The horn ran from 0.011 to 0.446, middle 0.157. And the
20 alert and mail sounds that ship with macOS, through `PitchAnalysis.frame`
in 4,800 sample blocks as the phone hands them over: 15 of the 20 were given
a pitch. Glass holds 391 to 393 Hz for six readings running, steadier than a
student and longer than a note had to be held to be ticked.

- **The silence floor is 0.010**, where it was 0.005. That takes all 13 hum
  readings and none of the horn's.
- **A pitch is passed on only once it is HELD** (`HeldPitch`): three readings
  in a row within half a semitone of each other, none of them under half the
  level of the loudest of the last three. The second half is the one that
  catches a chime. A chime's pitch is steady; what gives it away is that it
  was struck, and is dying from its first tenth of a second (Glass: 0.090,
  0.031, 0.015, 0.011). A blown note is as loud as the player blows it.
- **One reading somewhere else does not lose a held note**, which is the
  octave error the listener's median of three used to absorb. Two in a row is
  a new note.
- **The tick still comes six readings after the note starts.** The listener
  now holds back two, so `NoteConfirmation.readingsNeeded` went from six to
  four.
- **Every sound let go is logged with its reason** (`[LISTEN] IGNORED`, `LOST`,
  `HELD` in the debug file log). `LOST ... it was dying away` in the middle of
  a note, followed by `HELD` at the same pitch, is the gate dropping a real
  horn, and is what to look for after the next session.

**After, measured the same way.** 20 sounds, 8 places each could land in the
blocks, at full level, three tenths and one tenth: 480 runs. Before, 359 put
a pitch on the screen. After, 34: Game Center's invite, which ends on a note
it sustains (every run), Mail Fetch Error (1 reading at 95 Hz, 8 runs) and
Glass (1 reading, 2 runs). None is shown for more than three readings and a
tick needs four. The suite repeats this on every run against
the 18 of those sounds in `/System/Library/Sounds` and Mail, read off the Mac
the simulator runs on (`testNoMacAlertSoundCanBeTakenForANote`, four places
each: 58 of 72 runs pitched, 4 reach the screen). Nothing of Apple's is in the repo, and the
test skips with a message where the files cannot be read.

**In a real room, the same day.** Ryan tuned the trumpet again on the build
with the gate in it, and his mail sound went off in the middle of a note: the
needle did not move. That session's log: 31 notes held, 13 confirmed, 77
sounds with a pitch let go before they were shown.

**And what that log found wrong with the gate.** Ten of the 31 held notes
were dropped as "dying" and picked up again at the same pitch inside a
second, which on the screen is the reading going blank for three tenths of a
second in the middle of a note. Four were the attack, which is louder than
the note behind it; the rest were air sagging and coming back. So the rule
is now two numbers. While a sound is still being decided it must not fall
under half, as before, and that is where every chime is caught. A note that
is already held is only let go under a QUARTER (`dyingOnceHeld`). Chosen on
the same 480 runs: at a quarter no alert sound is shown for more than three
readings, at 0.15 Game Center's invite is shown for seven.

**Hand-built input:** the other six `HeldPitchTests`. The dying chime's
levels were read off Glass and typed in; the wandering horn, the sagging air
and the loud attack are made in the test from what the log showed.

**Not verified:**

- The 20 sounds went from their files straight into the detector. One real
  sound has been through a room and a phone, once.
- A horn through the two-number rule. The quarter is set from the chimes'
  side; from the horn's side there is only the count of ten drops under the
  old rule, not the levels they dropped to.
- A sound that really is a held note still reads as one: someone singing, a
  held note on a keyboard, the horn in the next chair. Every tuner has that.
- A room that hums louder than 0.010 still shows its hum. A range per
  instrument would stop that on three of the four horns and is not built.

## The check screen fits the phone (#35)

The tuner is used with a horn in both hands, and on Ryan's iPhone 16 Pro its
last line ran off the bottom whenever concert Bb was chosen. Measured off his
screenshots: concert F fitted with nothing to spare and concert Bb overflowed
by exactly the one line its caption wrapped onto. It had been fitting by luck.

- **Each thing is said once.** In the tuner the line under the picker and the
  line under "Hear it" said the same thing, so the second is gone there. The
  note check out of a chart has no picker and keeps it.
- **The screen measures itself** (`ViewThatFits` in `NoteCheckView`): the whole
  layout where it fits; a tighter one where it does not (shorter wave, no
  legend, no warm-up tip); and a scroll view only on a phone too short for
  that. Nothing that is USED is dropped in the tight one, and the microphone
  promise is never dropped.
- **The trap in it:** a `ViewThatFits` in a `VStack` is offered half the
  height, and picks the tight layout on a phone with room to spare. It is
  given `maxHeight: .infinity` for that reason.

Looked at in the simulator at the iPhone 17's height (the same 874 points as
the 16 Pro) and, with `-checkHeight 600`, as a shorter phone would show it.
**Not verified:** a real small phone. There is one simulator on the build Mac
and booting a second is what the script above exists to avoid.

    xcrun simctl launch booted com.massfeller.mellophone -tune YES -listenFake 353 -checkHeight 600

## The instrument is on every screen (#36)

Every fingering, concert key and listened-for pitch is worked out for one
instrument, and the only place that said which was a picker half way down the
Trainer. The first session with the tuner shows the cost in its log: opened
for a mellophone, closed, the instrument changed, opened again.

`InstrumentChip` is a drawing of the horn, its short name and a menu of the
four. It sits in a strip pinned over every tab (`PageScaffold`), in the
header of a chart and in the header of the note check and tuner.

- **The picture is the horn that is selected** (`BrassGlyph`, four drawings).
  The first build drew one generic horn for all four, on the argument that
  four brass silhouettes at 17 points could not be told apart. Ryan's answer
  was that a picture that does not match the horn tells nobody anything.
  They can be told apart when each is drawn by what sets it apart: a trumpet
  is long and slim, a mellophone is a short trumpet behind a bell as tall as
  the horn, a French horn is a coil with the bell hanging off it, a
  euphonium stands up with the bell at the top. Filled parts, no font and no
  image, like the clef. Each part is filled on its own, because two parts
  wound opposite ways in one path cut a hole where they cross.
- **On a strip of its own**, because "Note Recognition Drill" leaves no room
  beside it, and pinned, because its point is to be in the same corner
  whatever is on the screen.
- **Changing it on the note check or the tuner re-aims that screen.** Whoever
  opened it says what the same thing is on another horn (`retarget`): the same
  written note out of a chart, but a different written note for the same
  concert pitch in the tuner. The tuning note is found on the new horn's list
  by its concert name (`NoteCheckTarget.position`), never by its place: every
  horn lists its open note first, which is concert F on a mellophone and
  concert Bb on a trumpet, and keeping the place moved a student from F to Bb
  (#37). `testChangingHornsOnTheTunerKeepsTheConcertPitch` checks every pair
  of horns by the pitch they sound, with a control showing the old rule fails it.
- **Changing it on a chart stops the chart**, as changing the line does. What
  was playing was rendered at the old horn's pitch.
- **Every change is logged in one place**, `Preferences.instrument`, as
  `[INSTRUMENT]`, whichever control made it.
- The Trainer keeps its own picker. It is where the caveat about the horn's
  fingerings is said.

**Not verified:** on a phone. Looked at in the simulator only, and the menu
itself cannot be opened from a script.

## A chart sounds like the horn (#24)

Until October 2026 every sound in the app was the literal frequency of the
written note. That is right for the Trainer and the scales, which are about
reading, and wrong for a part, which is for playing along with: a mellophone
reading C sounds the F under it, so the app was a fifth above the student for
the whole chart, and "Hear it" on the note check (which had to be the sounding
pitch, because a microphone hears the real horn) disagreed with the same note
tapped in the bar list.

Now a chart plays at the pitch the selected instrument makes.

- **`Instrument.sounding(_:)` is the one place the factor lives.** The note
  check listens for it, "Hear it" plays it, the part plays it and a tapped note
  plays it. Two copies of that sum would be two chances for the app to call a
  student flat against its own sound.
- **`PartTimeline.Entry.frequency` is still the written pitch.** The staff, the
  valves and the note check all read the page. Only what is rendered moves:
  `PartTimeline.chunks` and `PartView.hear`. The note check is handed the
  written pitch and lowers it itself, so an entry that carried the sounding
  pitch would be lowered twice.
- **A timeline built with no instrument is the page as written**, with the
  plain tone. The bar list is laid out from one, and every test that names
  notes off the page uses one. The timeline that is HEARD comes from
  `PartModel.prepare(bpm:instrument:)`, where the instrument has no default.
- **The filter is held open to 700 Hz**, the same floor the note check's
  reference uses and for the same reason: a euphonium part goes down to 82 Hz
  and a phone speaker makes very little under about 300. The measurement is
  in `NoteCheckTests` (every note, every horn, energy left above 300 Hz).
  Notes that sound B4 (494 Hz) and up are not changed by it: the filter
  settles at one and a half times the pitch, which is over 700 from there.
  Everything under that is brighter in its held part than the plain tone,
  which takes in the middle of a mellophone part (written C5 to E5 sounds
  F4 to A4). This said "above the F over middle C" until #37.
- **The screen says whose pitch it is**, under the Sound chips, because a part
  played for the wrong horn is a fourth or more out and nothing else on the
  screen would say why.

The Trainer, the scales, the drill and the web app still play written pitch.
`index.html` is their spec and `ScalePitchTests` pins them there; changing
those is a change to both products and is not this.

**Measured** (`PartPlaybackTests`, 2026-10-12, iPhone 17 simulator):

| What was played | Notes | Heard at the horn's pitch | Worst |
|---|---|---|---|
| Sample chart, mellophone | 52 | 52 | under 0.05 cents |
| Sample chart, French horn | 52 | 52 | under 0.05 cents |
| Sample chart, trumpet | 52 | 52 | under 0.05 cents |
| Sample chart, euphonium | 52 | 52 | under 0.05 cents |
| A real mellophone part, top line, bars the reader is sure of | 200 | 200 | 1.9 cents |

The sample chart goes through the real reader out of the app bundle and is
rendered the way the player renders it. Each note is also required to be more
than 150 cents from the WRITTEN pitch, which is the control: the old behaviour
fails it on every note. The opening note is checked against a number typed in
by hand (written F4 is concert Bb3 on an F horn, 233.08 Hz).

The real part is one of Sam's charts and is not in the repo, so that test
skips on a clone. It has 326 notes on the top line; the 126 in bars the reader
flags as suspect are left out, because the reader is not sure what is in
them and this test is about pitch, not about the reader.

**Hand-built input:** `PartTimelineTests` and `PartModelTests` check what is
asked of the renderer (the frequency and the filter floor on each event, the
tapped note's pitch) on scores typed into the test. They prove the arithmetic,
not the sound.

**Not verified:** what it is like to play along with. Nobody has yet held a
horn up to a part playing at this pitch, and the brighter low notes have been
measured for energy and not listened to.

## The sample chart (#28)

A new install has no chart, and reading one is the centre of the app. So the
app ships one: `Mellophone/Resources/Sample Chart - Band Room March.pdf`,
sixteen bars written for this app. `ChartLibrary.withSample()` copies it into
the library on the first run and sets `mello-sample-chart-seeded`, so a student
who removes it does not get it back.

It is ours, and that is the whole condition for being in the bundle. Its
source is `scripts/sample-chart.musicxml`, written by
`scripts/make-sample-chart.py` from a table of notes, and MuseScore engraves
the PDF from that (the command is in the file's header). The tune is written to
use what the reader does: a key signature, a natural against it, beamed
eighths in twos and fours, dotted quarters, a rest inside a bar and two whole
bars of rest to count. `SampleChartTests` reads the bundled file with the real
importer and compares every note and length with the table it was composed
from.

## Beams are read as shapes (#29)

That test failed the first time it ran. Bars 2 and 13 of the sample, four
eighths under one beam, came back as four quarters.

The reader took a path for a beam when its BOUNDING BOX was 2 to 15 half-spaces
wide and 0.6 to 2.6 thick. A beam over four eighths measures 15.8 and 24.5
wide, and the ceiling could not just be raised, because it is what keeps out a
multi-measure rest's H-bar at 20 to 66. The box of a sloping beam is also
taller than the beam: 2.5 half-spaces around a slab 1.0 thick.

MuseScore fills a beam as a four cornered slab with upright ends, so
`ScoreBuilder` now reads the corners where they are there to read:

- thickness is the height of the slab's end, not of the box;
- whether a beam sits on a stem is asked at that stem's x, along the slope;
- a path wider than 15 is a beam only if it joins two stems that carry notes,
  which an H-bar never does.

A path with no corners, which is every beam the unit tests build by hand, is
judged by its box as before.

Measured on Sam's two charts, before and after, bar by bar. Florida reads
identically. PEAK changed in five bars and every change is a correction: bars
162, 166, 167 and 224 had four beamed eighths read as quarters, and three of
the four sixteenths in bar 240 were quarters and are now sixteenths. Three bars
left the suspect list (166, 167, 224) and none joined it.

**Was left wrong, fixed in #39:** the fourth sixteenth in that PEAK bar. It is
a note on the top line whose stem runs down to the bottom one, which is exactly
what a barline looks like. Keeping such a stem as a stem was tried twice here
and backed out, because it stayed a barline too. #39 found the same shape had
been adding bars all along (the bar numbers in this section were the reader's,
not the page's: "bar 240" is printed bar 235), and takes it out of the barlines
as well.

## The reader against Sam's charts (#39)

"Really bad at matching notes." Measured by reading both of Sam's charts in a
scratch harness and checking every bar against the rendered page, and against
the number the page prints at the start of every line.

| What was wrong | Where | Cause |
|---|---|---|
| Bar numbers drifted, +5 by the end of PEAK (reader 256, page 251) | PEAK from bar 27; Florida bar 18 cut in two | A stem exactly as tall as the staff (a note on the bottom line stem up, or on the top line stem down) read as a barline |
| Two whole bars vanished | Florida 14 and 35 | MuseScore draws the staff once per bar; the fitter's 40 point floor dropped a 39.68 point bar and everything in it |
| D played as Db | PEAK 34, 35 | A key change in the middle of a line was never read |
| Triplets played straight | PEAK 18, 49, 51, 68 to 72, 83 to 88, 185, 188, 198, 244 | Tuplet numbers are text glyphs (OpusTextStd, Edwin-Italic) and the reader drops text fonts |
| One note of a flagged chord played a quarter | Florida 7, 9, 40, 42 | The flag was asked about head by head |
| A second played as two notes in a row | PEAK 26 | Chords were grouped by x, and a second's heads sit either side of the stem |
| A sixteenth where a quarter is | PEAK 83 | A slur counted as two beams (stroke and fill) |
| A whole-bar rest read as four beats in 2/4 | PEAK 138 | A whole rest fills its bar in any meter |
| A natural lost through a tie | PEAK 51 | Ties were not read |

How each is told apart, all measured on the charts:

- **A stem is a staff-height line with a notehead on its end**: 2.50 to 2.63
  half-spaces left of it at the bottom line, or 0.13 right of it at the top.
  No real barline has a notehead nearer than 4.13 before or 2.67 after.
- **A key change is a run of accidentals that belong to no notehead,
  starting just after a barline.** All three on both charts sit at 2.19
  half-spaces.
- **A tuplet number is a lone digit with a bracket or a beam where a tuplet
  number's would be.** The bracket's two lines flank the number (left one ends
  0.4 before it, right one starts 3.2 after); without one, the beam it sits on
  is the span. Brackets are found before beams, because half a MuseScore
  bracket has the box of a beam.
- **A curve is never a beam.** `PlacedPath.hasCurves` is recorded by the PDF
  reader, since a curve keeps only its endpoint in `vertices`.
- **A tie is a level curve between NEIGHBOURING noteheads on the same step**,
  or from the start of a line to a note matching the last chord of the line
  before. The tied note takes the first one's spelling.

After: every line of PEAK (31) and of Florida (4) starts on the bar the page
prints, and neither chart has a suspect bar left (PEAK had 27, Florida 2).
`reader-traps.pdf`, engraved from `MellophoneTests/Fixtures/reader-traps.musicxml`,
holds one of each and is read bar by bar in `ChartReaderTrapsTests`; the same
file checks Sam's charts where they exist on the machine.

**Not fixed:** a tied note is still sounded again, through the 10 to 14 ms
phrase dip rather than a fresh attack, and without the scoop up to pitch. The
renderer works a few bars at a time and cannot hold one tone across two
buffers, and a tie across a barline is exactly that.

**Not verified:** any engraver but MuseScore 4 and Sibelius (Opus fonts), and
any chart but these two and our fixture. A Finale or Dorico part, or a scan,
has not been tried.

## The page's tempo (#41)

Sam asked why the app did not read the printed tempo and time signature and
default to them. Measured on both of his charts against the rendered pages:

- **The time signature was already read, and right.** PEAK is 4/4 with one bar
  of 2/4 at 138; Florida is 2/4. The reader has the same, bar for bar. What
  looked like the wrong number of notes in a bar on build 5 was the #39
  reader, which left 27 of PEAK's bars not adding up.
- **The tempo was not read at all.** Every glyph of a tempo mark is in a text
  font, and the reader drops text fonts when it gives glyphs to a staff. PEAK
  prints twelve tempos and Florida one; the app played both at one number.

How a mark is found (`Import/TempoMarks.swift`): a note glyph, an optional
dot, "=", digits, on one baseline with nothing but blanks between. The note is
a SMuFL metronome or note codepoint in any font (MuseScore's is U+ECA5 in
LelandText), or a letter in Sibelius's Opus Text (`q` is a quarter). A `q` in
any other font is a letter. Anything after the "=" but digits, a metric
modulation say, is not a tempo.

Where it takes effect: the staff under it, from the START of the bar it is
printed in. Not from the note under its left edge, because a word or a box
before the note pushes it right: "Part 2 A Tempo" put PEAK's 106 past its
whole multi-bar rest and "Fast" put 205 over the third rest of its bar. PEAK's
104 sits 0.81 half-spaces BEFORE the barline it follows, so a barline within 2
half-spaces ahead of a mark is the one it starts from (every other mark sits
3.63 or more after its barline). All twelve of PEAK's and Florida's one land on
the bar the page prints them over.

How it plays: the number by Play is the tempo the range starts at, and opens
at the page's for that bar ("as printed" under it). Slowing it is a SHARE of
the page, kept for the chart while it is open, and every later change plays at
the same share: PEAK at 90 from bar 1 plays bar 27's "Faster 160" at 120.
Tapping the number goes back to the page. A chart with no readable mark plays
at the student's own number throughout, `mello-part-tempo`, as before.
`PartTimeline` places each note from the last tempo change, never by adding up
note lengths, so a long section cannot drift.

**Not read:** ritardando and accelerando written as words, a mark printed in
the middle of a bar (it lands on the barline before it), a mark under the
staff, a metric modulation. Repeats were not played either until #46, below.

**Not verified:** Finale (Maestro) and Dorico marks. A Dorico mark should be
SMuFL codepoints and read, but no Dorico part has been tried. Not tried on a
phone.

## The director's page, as lyre cards (#43)

Sam reads songs he is still learning off lyre cards in a marching band flip
folder, and the bar list of note names taught him the names and not the page.
The card view shows the chart as the director's own page instead: a few
lines to a card, sideways, with the note being played boxed on it and the
rest of the page dimmed. It is the default ("The page"); "Note names" is the
old list, and both carry the switch (`mello-part-view`).

- **Nothing is redrawn.** Each line is cut out of the user's own PDF
  (`CardStrips`, `CGPDFPage`) and the box comes from where the reader found
  the notehead. Seven competing apps were read from their APKs on 2026-10-18
  and none reads the PDF itself; all seven turn the page into a picture, and
  only one boxes the exact note on the real page. Ours can because
  `ScoreBuilder` keeps every glyph's position (`NotePlace`, `SystemPlace`).
- **A line is cut to its own ink**, the tempo mark over it and the dynamics
  under it, and anything further than 14 half spaces over or 10 under is the
  page's (the title, the footer) and left out. Lines are stacked with no gap:
  the director's spacing between lines is what a lyre card throws away.
- **Four lines to a card** by default, 3 or 2 in the settings
  (`mello-card-lines`). Four PEAK lines are 352 points tall at full width and
  a phone on its side has about 310, so the card is fitted to the height.
- **The box follows the player's audio clock** through
  `PartModel.eventIDs(inSlot:)`; it has no clock of its own. The card turns
  on the downbeat of its first bar, and a card swiped to by hand while it
  plays comes back at the next note.
- **Touch:** tap a note to hear it, hold it to check it; tap a bar to start
  there; hold a bar and drag to loop. The hold comes first so it does not
  fight the swipe that turns the card.
- **Only this screen turns sideways** (`OrientationLock`). The plist allows
  landscape so the app can choose; the delegate answers portrait everywhere
  else. The note check opened from a card turns the phone upright again,
  because sideways its meter fell under the fold.
- **Printing** (`LyreCardPDF`): cards 17.8 x 13.4 cm for Sam's 18.0 x 13.6 cm
  sleeve, nothing in the top 2.2 cm (the ring strip, measured off the
  product photo), one scale for the whole chart so the staff is the same size
  on every card, a line never split. Letter or A4 two to a sheet with cut
  lines, or card size pages. Vector, built on the phone, out through the
  share sheet.
- **Checking it:** `PlacementTests`, `LyreCardsTests`, `CardGeometryTests`,
  `LyreCardPrintTests` on our own `card-turns` fixture (two pages, seven
  lines). Every PEAK card was rendered with every box drawn and looked at.

## Repeats and 1st and 2nd endings (#46)

The reader used to merge a repeat barline into a plain one, and the timeline
played the page top to bottom, so Florida played its 1st and 2nd endings back
to back and never went back to bar 7. A chart now plays the way a band
plays it: Florida is 1 to 38, 7 to 36, 39 to 42.

What the page prints, measured on Florida and on our own fixture:

- **A repeat sign is a pair of dots** (SMuFL U+E044) at steps 3 and 5 up from
  the bottom line. An end repeat's dots sit 1.7 to 1.8 half spaces BEFORE the
  first rule of their barline, a start repeat's 2.4 to 3.9 after it (3.9 is
  the :||: sign, three rules 7.3 points wide). Which side says which;
  `repeatDotReach` is 5.
- **A start repeat at the head of a line is not a barline.** A single staff
  has no barline at its left end, so MuseScore draws the start repeat after
  the clef and key, and the reader took it for a barline closing an empty
  bar: the fixture's 16 bars read as 17, numbered one high from line 3. A
  first barline with dots to its right and no note, rest or multi-bar rest
  before it is now dropped.
- **An ending is an unfilled bracket and a number.** One open path, up the
  hook and along the top (and down again on a closed ending), its hook 4.40
  half spaces tall with its foot 2.19 over the top line; "1." in a text font
  on the hook's foot. Both are required (`Import/RepeatMarks.swift`). It
  belongs to the bar its hook stands at.

How it plays (`Import/PlayOrder.swift`, pure arithmetic): an end repeat goes
back to the last start repeat before it, or with none, to the bar after the
last end repeat, or to the top; it is taken once, or once more for every extra
pass its endings name ("1. 2." then "3."). An ending is skipped on any pass
it does not name and runs to the end repeat that closes it. Bar numbers stay
the page's: bar 7 the second time is still bar 7.

- **The tempo follows the page.** A repeated bar plays at the tempo printed
  for it, wherever the performance has got to.
- **A range is cut from the performance**, from the first time its first bar
  comes up to the next time its last bar does. The whole part and the default
  opening at the entrance take the repeat, a loop of the 1st ending alone
  stays two bars, and a stretch inside the repeat plays once.
- **The bar list and the cards stay the page**, in printed order. The card
  turns back to bar 7 when the music does, and both screens say "Takes the
  repeat" when the range will.

**Checking it:** `RepeatTests`. The play order on hand-built marks; our own
`repeats` fixture (MuseScore 4, `MellophoneTests/Fixtures/repeats.musicxml`)
read end to end, holding an end repeat with no start, a :||:, a 1st ending at
the head of a line, a start repeat at the head of a line and a two-bar 1st
ending; Florida and PEAK where they exist. PEAK prints no repeat sign and still
reads bar for bar as it did before; so does Florida.

**Not read:** D.S., D.C., segno, coda and Fine; neither of Sam's charts prints
one, so there is nothing yet to measure against. A repeat sign or ending in a
Sibelius (Opus) part has not been seen, and neither has an ending bracket that
breaks across two lines.

## The wavetable cache

`SawtoothTable` caches single-cycle band-limited sawtooths by harmonic count.
The table depends only on how many harmonics fit under Nyquist, not on the
pitch, so there are at most 64 distinct tables in the app. Rebuilding per note
cost about 131,000 `sin()` calls each time and dominated rendering: the test
suite went from 53 seconds to 19 when this landed.

## The engine lies when it stalls

The single hardest bug in this app so far, and the one most likely to be
reintroduced by someone tidying up "defensive" code.

**Symptom:** the click died the moment the phone locked and the screen went
dark. It kept working when the app was merely backgrounded with the phone
unlocked.

**Everything that was NOT wrong**, each checked on the device rather than
reasoned about:

| checked | result |
|---|---|
| `UIBackgroundModes` in the built app | present |
| `UIBackgroundModes` read from inside the RUNNING process | present |
| background time iOS grants | unlimited, so it is treated as a background-audio app |
| `AVAudioSession` category | `.playback`, no options |
| `setActive(true)` during the stall | succeeds |
| `engine.isRunning` during the stall | `true` |
| player node `isPlaying` during the stall | `true` |
| the player's buffer queue during the stall | full |
| the device's render clock during the stall | still advancing |
| CoreHaptics (disabled for one build to test it) | not the cause |

Every indicator reported health while no sound came out. **The only signal that
told the truth was the player node's own sample time, which stopped moving.**
Rebuilding the audio graph brought the click back **on a still-dark screen**,
which is how we know the system had been willing to play the whole time.

**Fix:** `Metronome.detectAndRepairStall()`. The scheduler already wakes every
40 ms, so it watches the player's clock and, after half a second of no movement
with a full queue, tears the graph down and rebuilds it, resuming from the next
unplayed beat. Measured after the fix: one recovery at the moment of locking,
then skew flat at a constant offset for the rest of the run, which is a click
that is perfectly even and merely behind wall clock by the dead time it lost.
Even spacing is the job; wall alignment is not.

The queue-full condition is load-bearing. If the queue were empty, silence would
be our own fault for not feeding it, and restarting the engine would be the
wrong response and would mask a real scheduling bug.

**Two lessons worth keeping:**

1. **Do not trust `engine.isRunning`.** It stays `true` across a stall. So do
   `setActive`, the session state, and the device clock. Trust only whether the
   player's sample time advances.
2. **A debugger changes the answer.** The first "background audio works"
   evidence was gathered under `devicectl --console`, which holds the process
   alive and made a broken feature look fine. Diagnostics for anything involving
   suspension have to come from a file the app writes itself, launched from the
   home screen with nothing attached. See `FileLog`.

## A second bug the same investigation found

The scheduler used to compute its lookahead horizon from `player.playerTime`
and queue only the beats falling inside it. When that clock stalls, the horizon
freezes, so nothing is queued, so the player has nothing to render, so its clock
never advances. A deadlock where each half waits on the other.

Beats are now scheduled **back to back** with `at: nil`, four queued at a time,
so the scheduler never asks what time it is. Timing survives because each buffer
is one whole beat long and its LENGTH places the next beat, with the fractional
period absorbed by alternating between two adjacent lengths. See
`BeatSchedule.bufferLength(forOffset:)` and its tests.

## Haptics are foreground only

CoreHaptics will not play while the app is backgrounded or the device is locked.
That is an iOS rule, not a gap here. The click keeps going, the buzz does not,
and the toggle's subtitle says so, because a feature that silently stops working
reads as broken.

## Divergences from the web version

Recorded here and in issue #2, per its requirement that anything not carried
over is a conscious decision with a reason.

- **The drill's text field becomes a tap grid** (#5). Typing "Bb4" on a phone
  keyboard while holding a mellophone is the wrong input for the situation. Same
  question, same scoring, same enharmonic acceptance, one hand.
- **The fingering chart is a section of the Trainer tab**, not a permanently
  visible block below every panel. iOS collapses a sixth tab into a "More" list,
  which is worse than a scroll.
- **The staff maths is corrected**, per issue #8 and the section above.
- **The drill answers by tap grid**, not a text field. See below.
- **`mello-scale-speed` actually persists.** The web version writes it in
  `saveScaleSpeed` and never reads it back, so the setting does not survive a
  reload. Ported as a working preference rather than a faithful bug.
- **Imported charts are iOS only.** The web version has no file import and no
  PDF reader. Phase 4 of issue #19 is a decision, not a commitment.
- **The note check and the tuner are iOS only** (#22, #32). The web version
  has no microphone screen.
- **The instrument can be changed from any screen** (#36). The web version
  has one picker, on the trainer.
- **Dark only.** The web version is dark, band rooms are dim, and a white screen
  on a music stand at a night game is hostile.
- **iPhone-only, portrait, for v1.** An iPad version of a music-stand app is
  appealing and is not ruled out; shipping the configuration that is already
  proven comes first.
