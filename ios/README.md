# Mellophone Practice, iOS

The native app. The web version in this repo's `index.html` is the functional
specification and stays live as the fallback for anyone on Android or a
Chromebook.

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
  MUSICAL SYMBOL G CLEF the web version uses. Checked against all 264 font files
  in the iOS 26.5 runtime: zero hits. It would render as an empty box on a
  phone. Desktop browsers have a fallback that covers it, which is why the web
  version looks fine.
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

## The wavetable cache

`SawtoothTable` caches single-cycle band-limited sawtooths by harmonic count.
The table depends only on how many harmonics fit under Nyquist, not on the
pitch, so there are at most 64 distinct tables in the app. Rebuilding per note
cost about 131,000 `sin()` calls each time and dominated rendering: the test
suite went from 53 seconds to 19 when this landed.

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
- **Dark only.** The web version is dark, band rooms are dim, and a white screen
  on a music stand at a night game is hostile.
- **iPhone-only, portrait, for v1.** An iPad version of a music-stand app is
  appealing and is not ruled out; shipping the configuration that is already
  proven comes first.
