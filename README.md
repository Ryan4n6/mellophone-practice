# Honk It Up!

A practice tool for the mellophone, the French horn, the trumpet, the
euphonium (treble or bass clef) and the tuba. No install, no account, and it
opens with no signal once you have visited it.

**Open it:** https://mellophone.themassfellers.com/ (the first address, https://ryan4n6.github.io/mellophone-practice/, still serves the same page)

Same name and the same tool as the iOS app in `ios/`. The web version stays live
as the fallback for anyone on Android or a Chromebook, and its `NOTES` and
`SCALES` tables are the source of truth both products are built from.

## What's in it

- **Instrument picker**: mellophone, French horn, trumpet, euphonium in treble
  clef, euphonium in bass clef, or tuba. Fingerings, the staff, the range and
  the concert keys follow the choice, and it is remembered.
- **Same Fingering (Harmonic Series)**: the notes that share a valve combination,
  so you can see why your ear has to do the work the valves don't.
- **Scales & Exercises**: scale patterns to run against, each with what it is
  for.
- **Note Recognition Drill**: a note comes up, you name it.
- **Metronome**: on the audio clock, so it does not drift.
- **Practice Timer** and **Practice Log**.
- **Fingering Chart**: the full chart, always one scroll away.
- **Your Charts**: open the PDF of your own band part and the page reads the
  notes out of it, plays it back at your tempo at the pitch your horn makes,
  and follows it bar by bar. Your files stay in your browser.
- **Note check and tuner**: play a note and the page listens and says whether
  it is the right note and how many cents flat or sharp. The microphone is on
  for that screen only and nothing is kept.
- **English, Spanish and French**, and letter names or Do Re Mi.

The iOS app adds sideways flip folder cards, printed lyre cards, and a few kinds
of scanned PDF the browser cannot decode.

## Credits

The treble clef is [this one](https://www.svgrepo.com/show/98269/treble-clef)
from SVG Repo, and the bass clef is from [Bravura](https://github.com/steinbergmedia/bravura)
(SIL Open Font License). Both are inlined as path data rather than fetched, and
shared with the iOS app so both draw the same glyphs.

## Running it without the internet

Visit the page once, online. It keeps a copy of itself (`sw.js`, a service
worker) and opens from that copy afterwards with no signal: in a band room, on
a bus. When it is online it fetches any new version in the background, so an
update shows up the second time you open it. On an iPhone, Share then Add to
Home Screen puts it on the home screen with the app's icon.

Or download `index.html` and open it in any browser. Everything is in that one
file, so it runs from disk too, just without the offline copy.

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
