// scripts/check-metronome.js
//
// The web metronome's answer to ios/MellophoneTests/BeatScheduleTests.swift
// (#56). It runs the scheduler OUT OF index.html against an audio clock this
// script controls, and wakes it the way a browser does: late, by a different
// amount every time. Every click the scheduler books is recorded where the
// oscillator was told to start, which is what a listener hears.
//
//     node scripts/check-metronome.js
//
// Run it after touching anything under METRONOME in index.html.
const fs = require('fs');
const vm = require('vm');

const html = fs.readFileSync(require('path').join(__dirname, '..', 'index.html'), 'utf8');
const script = html.split('<script>')[1].split('</script>')[0].replace(/\ninit\(\);\n/, '\n');

// An AudioContext that only keeps time and writes down every oscillator start.
class FakeContext {
  constructor() { this.currentTime = 0; this.state = 'running'; this.starts = []; this.destination = {}; }
  createOscillator() {
    const ctx = this;
    return { type: '', frequency: { value: 0 }, connect() {}, start(t) { ctx.starts.push({ t, hz: this.frequency.value }); }, stop() {} };
  }
  createGain() { return { gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {} }; }
  resume() {}
}

const exposed = '\n;({ metroBeatTime, metroOffsetAtOrBefore, metroStart, metroPump, metroReanchor, setTempoValue: v => { tempo = v; }, setTimeSigValue: v => { timeSig = v; }, booked: () => metroBooked, next: () => metroNext });';
const ctx = {
  console: { log() {}, warn() {}, error: console.error },
  localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
  window: { AudioContext: FakeContext },
};
vm.createContext(ctx);
const m = vm.runInContext(script + exposed, ctx);
// getAudioCtx() makes one context and keeps it, so this is that one.
const audio = vm.runInContext('getAudioCtx()', ctx);

let failures = 0, checks = 0;
function ok(cond, what) { checks++; if (!cond) { failures++; console.log(`  FAIL ${what}`); } }
function group(name, fn) { console.log(name); fn(); }

// A browser timer: asked for every 25 ms, fires 0 to 18 ms after that, and on
// a slow machine now and then 60 ms late. Deterministic, so a failure repeats.
let seed = 12345;
function rand() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }
function runFor(seconds) {
  const end = audio.currentTime + seconds;
  while (audio.currentTime < end) {
    audio.currentTime += 0.025 + rand() * 0.018 + (rand() < 0.02 ? 0.06 : 0);
    m.metroPump();
  }
}

group('every click lands on anchor + i * period, however late the timer wakes', () => {
  audio.starts = [];
  m.setTempoValue(137); m.setTimeSigValue(4);
  m.metroStart(0.05);
  m.metroPump();
  runFor(600);                                   // ten minutes at 137
  const period = 60 / 137;
  let worst = 0;
  audio.starts.forEach((s, i) => { worst = Math.max(worst, Math.abs(s.t - (0.05 + i * period))); });
  ok(audio.starts.length >= Math.floor(600 / period), `booked ${audio.starts.length} clicks in ten minutes`);
  ok(worst < 1e-9, `worst click error ${worst} s`);
  // The thing setInterval got wrong: the old tick played at "now", so its
  // error was the timer's lateness, every beat.
  ok(audio.starts.every((s, i) => i === 0 || s.t > audio.starts[i - 1].t), 'no click booked twice or out of order');
  console.log(`  ${audio.starts.length} clicks, worst error ${worst.toExponential(2)} s`);
});

group('the downbeat is accented every bar', () => {
  const accents = audio.starts.map(s => s.hz === 1200);
  ok(accents.every((a, i) => a === (i % 4 === 0)), 'beat 1 of 4 is the 1200 Hz click, the rest 800 Hz');
});

group('a tempo change keeps the place in the bar and moves nothing booked', () => {
  audio.starts = []; audio.currentTime = 0;
  m.setTempoValue(120); m.setTimeSigValue(4);
  m.metroStart(0.05); m.metroPump();
  runFor(3.1);                                   // into beat 7 at 120
  const before = audio.starts.length;
  const lastBefore = audio.starts[before - 1].t;
  const beatInBar = (before - 1) % 4;
  m.setTempoValue(90);
  const lastBeat = beatInBar;
  m.metroReanchor((lastBeat + 1) % 4);
  runFor(4);
  const first = audio.starts[before];
  ok(Math.abs(first.t - (lastBefore + 60 / 90)) < 1e-9, `first click at the new tempo is one new period after the last booked one (${(first.t - lastBefore).toFixed(4)} s)`);
  const expectedAccent = (beatInBar + 1) % 4 === 0;
  ok((first.hz === 1200) === expectedAccent, 'the bar carries on from where it was');
  for (let i = before + 1; i < audio.starts.length; i++) {
    const gap = audio.starts[i].t - audio.starts[i - 1].t;
    if (Math.abs(gap - 60 / 90) > 1e-9) { ok(false, `gap ${gap} at click ${i}`); break; }
  }
});

group('a clock that ran past unbooked beats skips them on the same grid', () => {
  audio.starts = []; audio.currentTime = 0;
  m.setTempoValue(120); m.setTimeSigValue(4);
  m.metroStart(0.05); m.metroPump();
  runFor(1);
  const n = audio.starts.length;
  audio.currentTime += 5;                        // the tab slept for five seconds
  m.metroPump();
  const resumed = audio.starts.slice(n);
  ok(resumed.length <= 1, `woke to ${resumed.length} click(s), not a burst`);
  ok(resumed.every(s => Math.abs(((s.t - 0.05) / 0.5) - Math.round((s.t - 0.05) / 0.5)) < 1e-9), 'still on the beat grid');
  ok(resumed.every(s => s.t >= audio.currentTime - 1e-9), 'nothing booked in the past');
});

group('offset lookup agrees with the booked times exactly', () => {
  const sched = { anchor: 0.05, tempo: 137, startBeat: 0 };
  for (let k = 0; k < 20000; k++) {
    const t = m.metroBeatTime(sched, k);
    if (m.metroOffsetAtOrBefore(sched, t) !== k || m.metroOffsetAtOrBefore(sched, t - 1e-12) !== k - 1) {
      ok(false, `offset ${k} disagrees`); return;
    }
  }
  ok(true, 'agrees');
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
