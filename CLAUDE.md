# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A practice tool for the mellophone, the French horn and the trumpet: harmonic series, scales, note recognition drill, metronome, practice timer, practice log, fingering chart.

There are now **two products in this repo**, and they are built to different rules:

Both products are called **Honk It Up!** (#12). The Xcode target and this repo are still named for the mellophone, which is history, not the product name.

- **The web app**, `index.html`, is the whole original tool in one file (markup, styles, script, in that order). It stays live and is the fallback for anyone on Android or a Chromebook. Everything under "Hard constraint" and "Architecture" below is about this file.
- **The iOS app**, `ios/`, is a native SwiftUI app that treats `index.html` as its functional specification. It is not a web view wrapper, and the reasons are in issue #2 and `ios/README.md`. Read `ios/README.md` before touching anything in `ios/`.

The data tables in `index.html` (`NOTES`, `SCALES`) are the source of truth for **both** products. A correction goes into `index.html` first, then gets carried into the Swift model with `python3 ios/scripts/sync-note-data.py`.

**The fingering chart is derived, not remembered, in both products.** Open notes are written C4, G4, C5, E5, G5, C6; everything else is the nearest partial above it lowered by valves (2 = 1 semitone, 1 = 2, 1+2 = 3, 2+3 = 4, 1+3 = 5, 1+2+3 = 6). Three valves reach six, which is why the lowest note is F#3 and not F3. The generator refuses to run if the table disagrees, `FingeringChartTests` asserts the same about the shipped data, and the web app's `verifyFingerings()` re-checks it in the browser on every load and logs `[FINGERING]`. Seven rows were wrong once (#9) and the drill prints fingerings as corrective feedback, so a wrong value teaches the wrong thing.

**Fingerings are per-instrument and derived, never stored per instrument** (`Model/Instrument.swift`, and its twin `INSTRUMENTS` / `fingeringFor` / `scaleDisplayName` in `index.html` since #11). Mellophone and trumpet share a chart; French horn does not, because its F side sits an octave lower in the harmonic series, so written E4 is open on horn and `1+2` on the other two. Scale names store the WRITTEN key as fact and compute the concert half, since written F is concert Bb on an F instrument and concert Eb on a trumpet. `InstrumentTests` pins all of it against published charts. The two implementations are the same derivation on purpose: change one and change the other.

**Range:** F#3 to C6 is the instrument's span and what is expected of a drum corps lead player. The practice range defaults to C4 to G5, which is where a high school player lives.

## Commands

The web app has no build, no bundler and no package manager. It has one check script, which is developer tooling and never ships.

- Run it: `open index.html` (or drag it into a browser).
- Check the fingering derivation: `node scripts/check-instruments.js`. Same published trumpet and Single F Horn charts `InstrumentTests` uses on the iOS side, plus the stored `NOTES` table. Run it after touching `NOTES`, `SCALES`, `INSTRUMENTS` or `fingeringFor`.
- Deploy: push to `main`. GitHub Pages serves the repo root at https://ryan4n6.github.io/mellophone-practice/.

## Hard constraint: nothing loads over the network

No CDN scripts, no external stylesheets, no web fonts, no remote images, no fetch. The point of the app is that it works in a band room or on a bus with no signal, so every asset must be inline. The treble clef and accidentals are Unicode glyphs in a generic `serif`; the UI font is the system stack. Do not introduce a dependency that requires a build step or a request, and do not split the file.

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

### Divergences from the web version

Deliberate, and listed in `ios/README.md` with reasons. The notable one: the drill's text field becomes a tap grid, because typing "Bb4" on a phone keyboard while holding a horn is the wrong input for the situation.
