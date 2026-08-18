# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A practice tool for the mellophone: harmonic series, scales, note recognition drill, metronome, practice timer, practice log, fingering chart.

There are now **two products in this repo**, and they are built to different rules:

- **The web app**, `index.html`, is the whole original tool in one file (markup, styles, script, in that order). It stays live and is the fallback for anyone on Android or a Chromebook. Everything under "Hard constraint" and "Architecture" below is about this file.
- **The iOS app**, `ios/`, is a native SwiftUI app that treats `index.html` as its functional specification. It is not a web view wrapper, and the reasons are in issue #2 and `ios/README.md`. Read `ios/README.md` before touching anything in `ios/`.

The data tables in `index.html` (`NOTES`, `SCALES`) are the source of truth for **both** products. A correction goes into `index.html` first, then gets carried into the Swift model.

## Commands

The web app has no build, no bundler, no package manager, no test suite.

- Run it: `open index.html` (or drag it into a browser).
- Deploy: push to `main`. GitHub Pages serves the repo root at https://ryan4n6.github.io/mellophone-practice/.

## Hard constraint: nothing loads over the network

No CDN scripts, no external stylesheets, no web fonts, no remote images, no fetch. The point of the app is that it works in a band room or on a bus with no signal, so every asset must be inline. The treble clef and accidentals are Unicode glyphs in a generic `serif`; the UI font is the system stack. Do not introduce a dependency that requires a build step or a request, and do not split the file.

## Architecture

### `NOTES` is the source of truth

One array of `{ name, freq, staffPos, finger, accidental }` at the top of the script drives everything downstream: the fingering chart, the range dropdowns, the drill pool, the harmonic-series card, and scale playback (scales store note *names* and look them up in `NOTES`). Adding or correcting a note means editing that one row.

- `freq` is the literal frequency of the named pitch. No F-transposition is applied to audio. The mellophone's transposition shows up only in the `SCALES` labels, which name both ("Concert Bb (Written F)").
- `finger` is a display string that doubles as an equality key. The "Same Fingering (Harmonic Series)" card is `NOTES.filter(n => n.finger === note.finger)`, and the valve diagram lights up via `finger.includes('1'|'2'|'3')`. So the strings must be written consistently: `"1+2"`, never `"2+1"`.
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

`localStorage`, keys prefixed `mello-`: `mello-range-low`, `mello-range-high`, `mello-scale-speed`, `mello-practice-log`. The practice log is a JSON array of `{date, seconds}`, newest first, capped at 50 entries. Note that `mello-scale-speed` is written by `saveScaleSpeed` but never read back on load, so the speed select does not actually persist. `saveSession` silently ignores sessions under 10 seconds.

## The iOS app (`ios/`)

Full detail is in `ios/README.md`. What matters before you touch it:

- **`ios/project.yml` is the source of truth**, not `Mellophone.xcodeproj`. The project is generated by XcodeGen and is committed only so a clone opens in Xcode. Anything hand-edited in the pbxproj is silently reverted by the next `xcodegen generate`, and the drift stays invisible until an upload fails. That includes `CURRENT_PROJECT_VERSION`.
- **Several build settings are load-bearing and were paid for with real App Store failures** in the sibling repo `Ryan4n6/TPS-iOS`. Each is commented in `project.yml` with the outage it prevents. Do not tidy them away. The expensive one is `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO`, without which every build lands as "Missing Compliance", invisible to TestFlight testers.
- **Nothing goes over the network, ever.** No accounts, no analytics, no crash reporting SDK, no ads, no `URLSession`. The users are likely to include minors, the privacy label reads "Data Not Collected", and there is no backend. If a feature seems to need a server, that goes back to issue #2 as a decision, it does not get implemented.
- **The metronome's timing is the product.** `Audio/BeatSchedule.swift` computes every beat from a fixed anchor (`beat(i) = anchor + round(i * period)`) rather than by advancing a cursor, because an accumulating cursor is what makes the web version drift. `MellophoneTests/BeatScheduleTests` measures the difference. If you change that file, run those tests.
- **The scheduler is allowed to be late; the schedule is not.** A `DispatchSourceTimer` keeps 250 ms of clicks queued with explicit `AVAudioTime` sample positions. Never move click timing onto a `Timer`, a `DisplayLink`, or a completion handler.
- **Beat dots and haptics read the audio clock**, they do not run their own timer, so the display cannot drift against the sound.
- Debug builds show a live timing readout at the bottom of the Metronome tab: beats, audio-clock vs wall-clock elapsed, skew, worst schedule error. That panel is how timing claims get answered with a measurement instead of an assertion.

### Running it on hardware

`bash ios/scripts/run-device.sh` builds, signs headlessly against the Massfeller LLC App Store Connect key, installs and launches with `--terminate-existing`. That last flag matters: installing over a running app does not restart it, so without it you screenshot the old build.

### Divergences from the web version

Deliberate, and listed in `ios/README.md` with reasons. The notable one: the drill's text field becomes a tap grid, because typing "Bb4" on a phone keyboard while holding a horn is the wrong input for the situation.
