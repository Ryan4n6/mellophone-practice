# Mellophone Practice Companion

A practice tool for the mellophone, the French horn and the trumpet. One file, no
install, no account, works offline once the page has loaded.

**Open it:** https://ryan4n6.github.io/mellophone-practice/

## What's in it

- **Instrument picker** — mellophone, French horn or trumpet. Fingerings and
  concert keys follow the choice and it is remembered; everything else reads
  written pitch and does not care which horn you hold.
- **Same Fingering (Harmonic Series)** — the notes that share a valve combination,
  so you can see why your ear has to do the work the valves don't.
- **Scales & Exercises** — scale patterns to run against.
- **Note Recognition Drill** — a note comes up, you name it.
- **Metronome** — adjustable tempo.
- **Practice Timer** — for timed sessions.
- **Practice Log** — what you worked on and for how long.
- **Fingering Chart** — the full chart, always one scroll away.

## Running it without the internet

Download `index.html` and open it in any browser. Everything is in that one file —
no scripts, styles, or fonts are fetched from anywhere else, so it works on a
laptop with no signal, in a band room, on a bus.

## Editing it

`index.html` is the whole project. Open it in any text editor. The markup, styles
and script are all in that file, in that order.

Fingerings are worked out from each instrument's harmonic series (`fingeringFor`),
not stored per instrument. The `NOTES` table's `finger` column stays the
mellophone source of truth, and `verifyFingerings` checks the derivation against
it on every load: open the console and you should see

    [FINGERING] 36 notes match the derived mellophone chart

If you have node handy, `node scripts/check-instruments.js` checks the same thing
plus every instrument against published trumpet and single F horn charts. It is
developer tooling; nothing it touches is shipped or loaded by the page.
