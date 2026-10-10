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

## Three instruments, two differences

`Model/Instrument.swift`. Most of the app was already instrument-agnostic
without anyone intending it: the staff, the reading drill, the metronome and the
timer all depend on written pitch. Only two things differ per instrument.

**Fingerings.** A mellophone and a trumpet sit in the same place in the harmonic
series relative to their written notes, so they share a chart. A French horn's F
side sits an OCTAVE LOWER, which packs more partials into the staff and gives it
many more open notes:

| | open written notes |
|---|---|
| Mellophone, trumpet | C4, G4, C5, E5, G5, C6 |
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
marked 120 is felt in two. The reader does not read the tempo mark, so the
number is the student's, and the screen says what it counts.

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
- **Dark only.** The web version is dark, band rooms are dim, and a white screen
  on a music stand at a night game is hostile.
- **iPhone-only, portrait, for v1.** An iPad version of a music-stand app is
  appealing and is not ruled out; shipping the configuration that is already
  proven comes first.
