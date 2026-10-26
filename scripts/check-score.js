// scripts/check-score.js
//
// The web app's chart reader and player held to the iOS app's, line for line
// (#58). For every chart in scripts/score-golden/, the reader block and the
// part code are run out of index.html and print what the Swift dump prints:
// every event's pitch, length, onset, tie and place on the page, every line
// and bar, the tempos, the repeats, the order the bars play in, the whole
// part's timeline at 100 for a mellophone, and the loudness of the first two
// chunks rendered. Any difference is a failure, and the line it is on is
// shown.
//
//     node scripts/check-score.js
//
// The golden files are made from the shipping Swift sources by
// scripts/score-golden/make-golden.sh. Sam's charts, where they are on this
// machine (ios/MellophoneTests/Fixtures/local/, never committed), are checked
// the same way against goldens in that folder; elsewhere they are skipped,
// and it says so.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
const reader = html.split('<script type="text/plain" id="chart-reader">')[1].split('</script>')[0];
const page = html.split('<script>')[1].split('</script>')[0].replace(/\ninit\(\);\n/, '\n');
const quiet = { log() {}, info() {}, warn() {}, error() {}, debug() {} };
const ctx = { console: quiet, localStorage: { getItem: () => null, setItem() {}, removeItem() {} } };
vm.createContext(ctx);
// The page script first, for NOTES and the instrument table, then the reader,
// the way the browser has them once loadChartReader has run.
vm.runInContext(page + '\n;globalThis.__page = { NOTES };', ctx);
vm.runInContext(reader, ctx);
const api = vm.runInContext('({ readScore, playOrderRuns, makeTimeline, timelineChunks, timelineSlotAt, timelineMeasureAt, timelineBeatAt, renderSequence, PDFDocument, readPageGeometry })', ctx);

const f = v => v.toFixed(4);
const sd = x => Number.isInteger(x) ? x.toFixed(1) : String(x);
function dump(bytes, name) {
  const r = api.readScore(bytes, name);
  if (r.error) return [`ERROR ${r.error}`];
  const s = r.score, out = [];
  for (const e of s.events) {
    const kind = e.isClap ? 'clap' : (e.note === null && e.outOfRangeName === null) ? 'rest' : (e.outOfRangeName !== null ? 'out' : 'note');
    const place = e.place ? `${e.place.system} ${f(e.place.x)} ${f(e.place.y)}` : '-';
    out.push(`E ${e.measure} v${e.voice} ${kind} ${e.writtenName || '-'} ${e.note ? e.note.name : '-'} on ${f(e.onsetBeats)} dur ${f(e.durationBeats)} tie ${e.tiedFromPrevious ? 1 : 0} at ${place}`);
  }
  s.systems.forEach((y, i) => out.push(`S ${i} page ${y.page} lines ${y.lineYs.map(f).join(',')} x ${f(y.x0)}..${f(y.x1)} hs ${f(y.halfSpace)} ink ${f(y.inkTop)} ${f(y.inkBottom)} bars ${y.bars.map(b => `${b.measure}:${f(b.x0)}-${f(b.x1)}`).join(' ')}`));
  out.push(`K key ${s.keySignature} time ${s.timeSignature.beats}/${s.timeSignature.unit} voices ${s.voiceCount}`);
  out.push(`U units ${[...s.beatUnits.keys()].sort((a, b) => a - b).map(k => `${k}:${s.beatUnits.get(k)}`).join(' ')}`);
  out.push(`X suspect ${[...s.suspectMeasures].sort((a, b) => a - b).join(',')}`);
  out.push(`Y unreadable ${s.unreadableSymbols.map(c => c.toString(16).toUpperCase().padStart(4, '0')).join(',')}`);
  out.push(`T tempos ${s.tempos.map(t => `${t.printed}@${t.measure}/${f(t.onsetBeats)}x${sd(t.noteQuarters)}`).join(' ')}`);
  const arr = set => `[${[...set].sort((a, b) => a - b).join(', ')}]`;
  out.push(`R starts ${arr(s.repeats.starts)} ends ${arr(s.repeats.ends)} endings [${[...s.repeats.endings.keys()].sort((a, b) => a - b).map(k => `"${k}:[${s.repeats.endings.get(k).join(', ')}]"`).join(', ')}]`);
  const rep = s.repeats, opt = v => v === null || v === undefined ? '-' : v;
  out.push(`J segno ${opt(rep.segno)} coda ${opt(rep.coda)} tocoda ${opt(rep.toCoda)} fine ${opt(rep.fine)} jumps ${[...rep.jumps.keys()].sort((a, b) => a - b).map(k => `${k}:${rep.jumps.get(k).back === 'daCapo' ? 'DC' : 'DS'}-${rep.jumps.get(k).until}`).join(',')}`);
  out.push(`O order ${api.playOrderRuns(s.playOrder)}`);
  const t = api.makeTimeline(s, 0, s.playOrder, 100, 'mellophone');
  out.push(`L duration ${f(t.duration)} spp ${f(t.secondsPerPulse)} countin ${t.countInBeats} pulse ${t.pulse.name}`);
  for (const e of t.entries) out.push(`N ${e.slot} ${e.event.measure} ${f(e.start)} ${f(e.duration)} ${e.frequency === null ? '-' : f(e.frequency)} ${e.articulation.tonguedIn ? 1 : 0}${e.articulation.carriesOn ? 1 : 0} ${f(e.articulation.settleCents)}`);
  for (const m of t.measures) out.push(`M ${m.number} ${f(m.start)}`);
  for (let k = 0; ; k++) {
    // Swift's stride over doubles multiplies, start + k * step, never sums.
    const x = k * 0.37;
    if (!(x < t.duration)) break;
    const sl = api.timelineSlotAt(t, x), me = api.timelineMeasureAt(t, x), be = api.timelineBeatAt(t, x);
    out.push(`A ${f(x)} ${sl === null ? '-' : sl} ${me === null ? '-' : me} ${be === null ? '-' : be}`);
  }
  api.timelineChunks(t, 48000).forEach((c, i) => {
    out.push(`C ${c.startFrame} ${c.frames} ${c.events.length}`);
    for (const e of c.events) out.push(`  e ${f(e.frequency)} ${f(e.onset)} ${f(e.duration)} ${e.isClap ? 1 : 0} ${f(e.isClap ? 0 : e.brightnessFloor)}`);
    if (i < 2) {
      const samples = api.renderSequence(c.events, 0.5, 48000, c.frames);
      let sum = 0, peak = 0;
      for (const v of samples) { sum += v * v; peak = Math.max(peak, Math.abs(v)); }
      out.push(`  r ${Math.sqrt(sum / Math.max(samples.length, 1)).toFixed(9)} ${peak.toFixed(9)}`);
    }
  });
  return out;
}

// The loudness lines compare within a hair: the two renderers agree to 1e-12
// on every sample, which can still tip the ninth decimal of a sum.
function same(a, b) {
  if (a === b) return true;
  const ma = /^ {2}r (\S+) (\S+)$/.exec(a), mb = /^ {2}r (\S+) (\S+)$/.exec(b);
  return !!(ma && mb && Math.abs(ma[1] - mb[1]) < 1e-7 && Math.abs(ma[2] - mb[2]) < 1e-7);
}

let failures = 0, charts = 0;
function check(pdf, golden) {
  charts++;
  const started = Date.now();
  const want = fs.readFileSync(golden, 'utf8').trimEnd().split('\n');
  const got = dump(new Uint8Array(fs.readFileSync(pdf)), path.basename(pdf));
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  const n = Math.max(want.length, got.length);
  let bad = 0, first = -1;
  for (let i = 0; i < n; i++) if (!same(want[i], got[i])) { bad++; if (first < 0) first = i; }
  const events = want.filter(l => l.startsWith('E ')).length;
  if (!bad) { console.log(`  same   ${path.basename(pdf)}: ${events} events, ${want.length} lines, ${seconds} s`); return; }
  failures++;
  console.log(`  FAIL   ${path.basename(pdf)}: ${bad} of ${n} lines differ, first at line ${first + 1}`);
  console.log(`    swift: ${want[first]}`);
  console.log(`    web:   ${got[first]}`);
}

const GOLDEN = path.join(__dirname, 'score-golden');
const FIX = path.join(ROOT, 'ios', 'MellophoneTests', 'Fixtures');
const sources = new Map(fs.readdirSync(FIX).filter(n => n.endsWith('.pdf')).map(n => [n.replace(/\.pdf$/, '').replace(/ /g, '_'), path.join(FIX, n)]));
sources.set('Sample_Chart_-_Band_Room_March', path.join(ROOT, 'ios', 'Mellophone', 'Resources', 'Sample Chart - Band Room March.pdf'));

console.log('our charts');
for (const g of fs.readdirSync(GOLDEN).filter(n => n.endsWith('.txt')).sort()) {
  const pdf = sources.get(g.replace(/\.txt$/, ''));
  if (!pdf) { failures++; console.log(`  FAIL   ${g}: no PDF for this golden file`); continue; }
  check(pdf, path.join(GOLDEN, g));
}
for (const name of sources.keys()) if (!fs.existsSync(path.join(GOLDEN, name + '.txt'))) { failures++; console.log(`  FAIL   ${name}: a chart with no golden file, run scripts/score-golden/make-golden.sh`); }

console.log("Sam's charts, local only");
const LOCAL = path.join(FIX, 'local');
const localGolden = path.join(LOCAL, 'golden');
if (fs.existsSync(localGolden)) {
  for (const g of fs.readdirSync(localGolden).filter(n => n.endsWith('.txt')).sort()) {
    const pdf = fs.readdirSync(LOCAL).find(n => n.replace(/\.pdf$/, '').replace(/ /g, '_') + '.txt' === g);
    if (pdf) check(path.join(LOCAL, pdf), path.join(localGolden, g));
  }
} else console.log('  SKIPPED: no ios/MellophoneTests/Fixtures/local/golden on this machine');

console.log(`\n${charts - failures}/${charts} charts read and play exactly as the iOS app reads and plays them`);
process.exit(failures ? 1 : 0);
