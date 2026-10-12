# Honk It Up!

A practice tool for the mellophone, the French horn, the trumpet and the
euphonium. One file, no
install, no account, works offline once the page has loaded.

**Open it:** https://ryan4n6.github.io/mellophone-practice/

Same name and the same tool as the iOS app in `ios/`. The web version stays live
as the fallback for anyone on Android or a Chromebook, and its `NOTES` and
`SCALES` tables are the source of truth both products are built from.

## What's in it

- **Instrument picker**: mellophone, French horn, trumpet or euphonium (treble
  clef parts). Fingerings and concert keys follow the choice and it is
  remembered; everything else reads written pitch and does not care which horn
  you hold.
- **Same Fingering (Harmonic Series)**: the notes that share a valve combination,
  so you can see why your ear has to do the work the valves don't.
- **Scales & Exercises**: scale patterns to run against.
- **Note Recognition Drill**: a note comes up, you name it.
- **Metronome**: adjustable tempo.
- **Practice Timer**: for timed sessions.
- **Practice Log**: what you worked on and for how long.
- **Fingering Chart**: the full chart, always one scroll away.

## What the iOS app adds

The iOS app in `ios/` does everything above and two things a web page cannot:

- **Your Charts**: open the PDF of your own band part, the one your director
  exported from the notation program, and the app reads the notes out of it,
  plays it back at your tempo and follows it bar by bar with the valves for
  each note. It plays at the pitch your instrument makes, so you can play
  along with it. A short sample chart is included so there is something to
  open on day one.
- **Note check**: hold a note in a chart, play it on your horn, and the app
  listens and says whether it is the right note and in tune, at the pitch your
  instrument actually sounds.

## Credits

The treble clef is [this one](https://www.svgrepo.com/show/98269/treble-clef)
from SVG Repo, inlined as path data rather than fetched, and shared with the iOS
app so both draw the same glyph.

## Running it without the internet

Download `index.html` and open it in any browser. Everything is in that one file:
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
plus every instrument against published trumpet, single F horn and euphonium
charts. It is
developer tooling; nothing it touches is shipped or loaded by the page.
