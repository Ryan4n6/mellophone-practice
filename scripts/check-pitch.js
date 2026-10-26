// scripts/check-pitch.js
//
// The web tuner and note check (#57), checked the way the iOS copy is in
// ios/MellophoneTests/NoteCheckTests.swift: the detector is calibrated against
// tones of known pitch made HERE before anything is judged with it, and every
// "it works" has a control that shows the check can fail. Runs the code out of
// index.html; node only, nothing ships.
//
//     node scripts/check-pitch.js
//
// What is real and what is not, said once. Every tone is synthesised in this
// file: steady overtones, and a 300 Hz high pass that is a GUESS at a phone's
// microphone. The iOS tests also use the app's own rendered tone; the web tone
// is live WebAudio and cannot be rendered in node, so a 24 harmonic sawtooth
// stands in for it. The alert sounds are the real files macOS ships, decoded
// with afconvert, and are skipped loudly anywhere else. No horn has been
// played into the web page.
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const script = html.split('<script>')[1].split('</script>')[0].replace(/\ninit\(\);\n/, '\n');
const exposed = '\n;({ NOTES, INSTRUMENTS, pitchCents, pitchFrame, risingCrossing, pitchTrace, HeldPitch, NoteConfirmation, makeCheck, checkSounding, checkSoundingName, checkTolerance, checkWrittenNameOfHeard, checkCents, checkVerdict, checkWords, tuningChecks, checkPosition, soundingFrequency, fingeringFor, LISTEN_WINDOW, LISTEN_SCOPE_WINDOW, TRACE_CYCLES, PITCH_QUIETEST, PITCH_LOWEST_HZ });';
const ctx = { console: { log() {}, info() {}, warn() {}, error() {} }, localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} } };
vm.createContext(ctx);
const P = vm.runInContext(script + exposed, ctx);

let failures = 0, checks = 0;
function ok(cond, what) { checks++; if (!cond) { failures++; console.log(`  FAIL ${what}`); } }
function near(a, b, tol, what) { ok(a !== null && a !== undefined && Math.abs(a - b) <= tol, `${what}: expected ${b} within ${tol}, got ${a}`); }
function group(name, fn) { console.log(name); fn(); }

const INSTRUMENT_KEYS = ['mellophone', 'frenchHorn', 'trumpet', 'euphonium'];
const RATE = 48000;
function note(name) { return P.NOTES.find(n => n.name === name); }
function check(name, key = 'mellophone', purpose = 'rightNote') { return P.makeCheck(name, note(name).freq, key, purpose); }
const kind = v => v.kind;

function harmonicTone(frequency, seconds = 0.6, rate = RATE, harmonics = 12) {
  const out = new Float64Array(Math.floor(seconds * rate));
  for (let n = 0; n < out.length; n++) {
    let s = 0;
    for (let h = 1; h <= harmonics; h++) s += Math.sin(2 * Math.PI * frequency * h * n / rate) / h;
    out[n] = s * 0.2;
  }
  return out;
}
// A guess at a phone: everything under `cut` taken away, 24 dB an octave.
function highPassed(samples, cut = 300, rate = RATE) {
  let x = samples;
  for (let pass = 0; pass < 2; pass++) {
    const w = 2 * Math.PI * cut / rate, alpha = Math.sin(w) / (2 * 0.7071), c = Math.cos(w);
    const b0 = (1 + c) / 2, b1 = -(1 + c), b2 = (1 + c) / 2, a0 = 1 + alpha, a1 = -2 * c, a2 = 1 - alpha;
    const y = new Float64Array(x.length);
    for (let n = 2; n < x.length; n++) y[n] = (b0 * x[n] + b1 * x[n - 1] + b2 * x[n - 2] - a1 * y[n - 1] - a2 * y[n - 2]) / a0;
    x = y;
  }
  return x;
}
const steady = (s, count = P.LISTEN_WINDOW, rate = RATE) => s.slice(Math.floor(0.25 * rate), Math.floor(0.25 * rate) + count);
// The stand-in for the app's own tone: brassy, a sawtooth to 24 harmonics.
const brassy = (f, count = P.LISTEN_WINDOW) => steady(harmonicTone(f, 0.6, RATE, 24), count);
function sine(f, phase = 0, count = P.LISTEN_WINDOW) { return Float64Array.from({ length: count }, (_, n) => Math.sin(2 * Math.PI * f * n / RATE + phase) * 0.3); }
function amount(f, w) { let re = 0, im = 0; w.forEach((v, n) => { re += v * Math.cos(2 * Math.PI * f * n / RATE); im += v * Math.sin(2 * Math.PI * f * n / RATE); }); return 2 * Math.hypot(re, im) / w.length; }

// ---------------------------------------------------------------- calibrate

group('the detector names tones of known pitch, under where the app plays too', () => {
  for (const f of [58.27, 77.78, 87.31, 98.0, 110.0, 123.47, 138.59, 233.08, 349.23, 466.16, 698.46, 1046.5]) {
    for (const harmonics of [1, 8, 24]) {
      const heard = P.pitchFrame(steady(harmonicTone(f, 0.6, RATE, harmonics)), RATE).frequency;
      near(heard === null ? null : P.pitchCents(heard, f), 0, 5, `${f} Hz with ${harmonics} harmonics`);
    }
  }
});

group('a note a few cents out is read to half a cent at every tuning pitch', () => {
  const seen = [];
  for (const key of INSTRUMENT_KEYS) for (const c of P.tuningChecks(key)) {
    if (!seen.some(s => Math.abs(P.checkSounding(s) - P.checkSounding(c)) < 0.01)) seen.push(c);
  }
  ok(JSON.stringify(seen.map(c => Math.round(P.checkSounding(c))).sort((a, b) => a - b)) === '[175,233,349,466]', 'four tuning sounds');
  let worst = 0, readings = 0;
  for (const c of seen) for (const rate of [44100, 48000]) for (const filtered of [false, true]) {
    for (let offset = -40; offset <= 40; offset += 5) {
      const played = P.checkSounding(c) * Math.pow(2, offset / 1200);
      const from = filtered ? Math.floor(0.1 * rate) : 0;
      let samples = harmonicTone(played, (from + P.LISTEN_WINDOW + 1) / rate, rate);
      if (filtered) samples = highPassed(samples, 300, rate);
      const heard = P.pitchFrame(samples.slice(from, from + P.LISTEN_WINDOW), rate).frequency;
      const label = `${P.checkSounding(c).toFixed(2)} Hz ${offset} cents at ${rate}${filtered ? ', nothing under 300' : ''}`;
      if (heard === null) { ok(false, `no pitch: ${label}`); continue; }
      const error = Math.abs(P.pitchCents(heard, played));
      worst = Math.max(worst, error); readings++;
      ok(error < 0.5, `${label}: off by ${error}`);
      if (Math.abs(Math.abs(offset) - P.checkTolerance(c)) <= 0.5) continue;
      const v = P.checkVerdict(c, heard);
      if (v.kind === 'inTune') ok(Math.abs(offset) < P.checkTolerance(c), label);
      else if (v.kind === 'sharp') ok(offset > P.checkTolerance(c), label);
      else if (v.kind === 'flat') ok(offset < -P.checkTolerance(c), label);
      else ok(false, `${label}: ${v.kind}`);
    }
  }
  ok(readings === 272, `272 readings, got ${readings}`);
  console.log(`  ${readings} readings, worst ${worst.toFixed(3)} cents`);
});

group('every note at its sounding pitch on every horn is heard in tune, and a semitone out is caught', () => {
  let worst = 0;
  for (const key of INSTRUMENT_KEYS) for (const n of P.NOTES) {
    const c = P.makeCheck(n.name, n.freq, key);
    const heard = P.pitchFrame(brassy(P.checkSounding(c)), RATE).frequency;
    if (heard === null) { ok(false, `${n.name} on ${key}: nothing heard`); continue; }
    worst = Math.max(worst, Math.abs(P.pitchCents(heard, P.checkSounding(c))));
    ok(P.checkVerdict(c, heard).kind === 'inTune', `${n.name} on ${key}`);
  }
  ok(worst < 5, `worst ${worst} cents`);
  // The control: a detector that said yes to anything would pass the above.
  for (const n of P.NOTES) {
    const c = P.makeCheck(n.name, n.freq, 'mellophone');
    const v = P.checkVerdict(c, P.pitchFrame(brassy(P.checkSounding(c) * Math.pow(2, 1 / 12)), RATE).frequency);
    ok(v.kind === 'wrongNote' && v.tooHigh, `${n.name}: a semitone sharp was judged ${v.kind}`);
  }
  console.log(`  worst ${worst.toFixed(3)} cents over ${P.NOTES.length * 4} notes`);
});

group('a euphonium is heard through a microphone that cannot hear its fundamental, and its pedal is named', () => {
  for (const n of P.NOTES) {
    const c = P.makeCheck(n.name, n.freq, 'euphonium');
    const whole = harmonicTone(P.checkSounding(c));
    const filtered = steady(highPassed(whole));
    if (P.checkSounding(c) < 150) ok(amount(P.checkSounding(c), filtered) < amount(P.checkSounding(c), steady(whole)) / 10, `${n.name}: the filter left the fundamental in`);
    const heard = P.pitchFrame(filtered, RATE).frequency;
    ok(heard !== null && P.checkVerdict(c, heard).kind === 'inTune', `${n.name} at ${P.checkSounding(c).toFixed(2)} with no fundamental: heard ${heard}`);
  }
  const low = check('F#3', 'euphonium');
  for (const [what, w] of [['whole', steady(harmonicTone(58.27))], ['no fundamental', steady(highPassed(harmonicTone(58.27)))]]) {
    const heard = P.pitchFrame(w, RATE).frequency;
    near(heard && P.pitchCents(heard, 58.27), 0, 5, `the pedal, ${what}`);
    const v = P.checkVerdict(low, heard);
    ok(v.kind === 'wrongNote' && v.writtenName === 'C3' && !v.sameValves && !v.tooHigh, `the pedal is written C3 on a euphonium (${what})`);
  }
});

group('silence, noise and a faint note are not notes', () => {
  ok(P.pitchFrame(new Float64Array(P.LISTEN_WINDOW), RATE).frequency === null, 'silence');
  let seed = 0x9E3779B9;
  const next = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296 * 2 - 1; };
  for (let trial = 0; trial < 20; trial++) {
    const noise = Float64Array.from({ length: P.LISTEN_WINDOW }, () => next() * 0.2);
    const frame = P.pitchFrame(noise, RATE);
    ok(frame.level > P.PITCH_QUIETEST, 'the noise is loud enough to be looked at');
    ok(frame.frequency === null, `trial ${trial}: white noise was given ${frame.frequency} Hz`);
  }
  const faint = brassy(349.23).map(v => v * 0.005);
  const frame = P.pitchFrame(faint, RATE);
  ok(frame.level < P.PITCH_QUIETEST && frame.frequency === null, 'under the floor');
});

// ---------------------------------------------------------------- judging

group('what the horn sounds', () => {
  near(P.checkSounding(check('C5', 'mellophone')), 349.23, 0.01, 'mellophone C5');
  near(P.checkSounding(check('C5', 'frenchHorn')), 349.23, 0.01, 'horn C5');
  near(P.checkSounding(check('C5', 'trumpet')), 466.16, 0.01, 'trumpet C5');
  near(P.checkSounding(check('C5', 'euphonium')), 233.08, 0.01, 'euphonium C5');
  near(P.checkSounding(check('F#3', 'euphonium')), 82.41, 0.01, 'euphonium F#3');
  ok(P.checkSoundingName(check('C5')) === 'F4', 'concert F4');
  ok(P.checkSoundingName(check('C5', 'trumpet')) === 'Bb4', 'concert Bb4');
  ok(P.checkSoundingName(check('Ab4')) === 'Db4', 'concert pitch is named in flats');
  ok(P.checkSoundingName(check('F#3', 'euphonium')) === 'E2', 'euphonium low E');
  ok(P.checkWrittenNameOfHeard(check('C5', 'euphonium'), 233.08) === 'C5', 'euphonium heard back');
  ok(P.checkWrittenNameOfHeard(check('C5', 'trumpet'), 233.08) === 'C4', 'trumpet heard back');
});

group('a horn playing the note is in tune and the app\'s own written pitch is not', () => {
  const c5 = check('C5');
  ok(P.checkVerdict(c5, 349.23).kind === 'inTune', '349 Hz is a mellophone C5');
  const v = P.checkVerdict(c5, c5.writtenFrequency);
  ok(v.kind === 'wrongNote' && v.writtenName === 'G5' && v.sameValves && v.tooHigh, `523 Hz is written G5, got ${JSON.stringify(v)}`);
});

group('inside twenty cents is in tune, past it flat or sharp by that much', () => {
  const c5 = check('C5'); const off = c => P.checkSounding(c5) * Math.pow(2, c / 1200);
  for (const c of [-19.9, -7, 0, 12, 19.9]) ok(P.checkVerdict(c5, off(c)).kind === 'inTune', `${c} cents`);
  const flat = P.checkVerdict(c5, off(-33)); ok(flat.kind === 'flat' && Math.abs(flat.cents - 33) < 0.01, '-33 flat');
  const sharp = P.checkVerdict(c5, off(41)); ok(sharp.kind === 'sharp' && Math.abs(sharp.cents - 41) < 0.01, '+41 sharp');
  near(P.checkCents(c5, off(-33)), -33, 0.01, 'cents');
  ok(P.checkVerdict(c5, null).kind === 'nothing' && P.checkCents(c5, null) === null, 'nothing heard');
});

group('a wrong note is named as written and says whether the valves were right', () => {
  const c5 = check('C5'); const s = n => P.checkSounding(check(n));
  const eq = (v, name, same, high, what) => ok(v.kind === 'wrongNote' && v.writtenName === name && v.sameValves === same && v.tooHigh === high, `${what}: ${JSON.stringify(v)}`);
  eq(P.checkVerdict(c5, s('G4')), 'G4', true, false, 'G4');
  eq(P.checkVerdict(c5, s('E5')), 'E5', true, true, 'E5');
  eq(P.checkVerdict(c5, s('B4')), 'B4', false, false, 'B4');
  ok(P.checkWrittenNameOfHeard(check('C5', 'trumpet'), 261.63) === 'D4', 'concert C4 is written D4 on trumpet');
  ok(P.checkWrittenNameOfHeard(check('C5'), 261.63) === 'G4', 'and G4 on mellophone');
});

group('the words match the verdict', () => {
  const c5 = check('C5'); const w = (v, c) => P.checkWords(c5, v, c);
  ok(w({ kind: 'nothing' }, false).headline === 'Play it and hold it', 'nothing');
  ok(w({ kind: 'inTune', cents: 3 }, false).headline === "That's C5", 'in tune');
  ok(w({ kind: 'inTune', cents: 3 }, true).headline === "That's it", 'confirmed');
  ok(w({ kind: 'inTune', cents: 3 }, true).detail === 'C5, Open', 'confirmed detail');
  ok(w({ kind: 'flat', cents: 32.6 }, false).detail === '33 cents low', 'flat');
  ok(w({ kind: 'sharp', cents: 24.2 }, false).detail === '24 cents high', 'sharp');
  ok(w({ kind: 'wrongNote', writtenName: 'G4', sameValves: true, tooHigh: false }, false).detail === 'Right valves, wrong note. Aim higher.', 'same valves');
  ok(w({ kind: 'wrongNote', writtenName: 'B4', sameValves: false, tooHigh: false }, false).detail === 'C5 is Open. Aim higher.', 'other valves');
});

group('each horn tunes to the notes a band calls, open note first', () => {
  const expected = {
    mellophone: [['F', 'C5', 349.23, 'Open'], ['Bb', 'F4', 233.08, '1']],
    frenchHorn: [['F', 'C5', 349.23, 'Open'], ['Bb', 'F4', 233.08, '1']],
    trumpet: [['Bb', 'C5', 466.16, 'Open'], ['F', 'G4', 349.23, 'Open']],
    euphonium: [['Bb', 'C5', 233.08, 'Open'], ['F', 'G4', 174.61, 'Open']],
  };
  ok(JSON.stringify(Object.keys(expected).sort()) === JSON.stringify(Object.keys(P.INSTRUMENTS).sort()), 'a horn was added without tuning notes');
  for (const key of INSTRUMENT_KEYS) {
    const got = P.tuningChecks(key);
    ok(got.length === expected[key].length, `${key}: a tuning note was dropped`);
    got.forEach((c, i) => {
      const [concert, written, hz, fingering] = expected[key][i];
      ok(c.choice === 'Concert ' + concert && c.writtenName === written && c.purpose === 'tuning', `${key} ${concert}`);
      near(P.checkSounding(c), hz, 0.01, `${key} concert ${concert}`);
      ok(P.checkSoundingName(c).startsWith(concert), `${key}: ${P.checkSoundingName(c)} is not a concert ${concert}`);
      ok(P.fingeringFor(written, key) === fingering, `${key} ${written} fingering`);
    });
  }
});

group('the tuner is stricter than the note check and says which way the slide goes', () => {
  const checking = check('C5'); const tuning = check('C5', 'mellophone', 'tuning');
  const off = c => P.checkSounding(checking) * Math.pow(2, c / 1200);
  ok(P.checkTolerance(checking) === 20 && P.checkTolerance(tuning) === 10, 'tolerances');
  for (const c of [-9.9, -4, 0, 6, 9.9]) ok(P.checkVerdict(tuning, off(c)).kind === 'inTune', `${c} on the tuner`);
  ok(P.checkVerdict(checking, off(15)).kind === 'inTune', 'the check accepts 15');
  ok(P.checkVerdict(tuning, off(15)).kind === 'sharp', 'the tuner calls 15 sharp');
  ok(P.checkVerdict(tuning, off(-12)).kind === 'flat', 'the tuner calls -12 flat');
  const w = (v, c) => P.checkWords(tuning, v, c);
  ok(w({ kind: 'sharp', cents: 14.4 }, false).headline === 'Sharp', 'Sharp');
  ok(w({ kind: 'sharp', cents: 14.4 }, false).detail === '14 cents high. Pull your tuning slide out a little.', 'sharp comes OUT');
  ok(w({ kind: 'flat', cents: 22.6 }, false).detail === '23 cents low. Push your tuning slide in a little.', 'flat goes in');
  ok(w({ kind: 'inTune', cents: -3.2 }, false).detail === '3 cents low. Hold it steady.', 'in tune low');
  ok(w({ kind: 'inTune', cents: 1.1 }, true).detail === '1 cent high. Leave the slide there.', 'one cent');
  ok(w({ kind: 'inTune', cents: 0.3 }, true).detail === 'Dead on. Leave the slide there.', 'dead on');
  ok(w({ kind: 'wrongNote', writtenName: 'G4', sameValves: true, tooHigh: false }, false).detail === 'Right valves, wrong note. Aim higher.', 'wrong note on the tuner');
  ok(P.checkWords(checking, { kind: 'sharp', cents: 24.2 }, false).detail === '24 cents high', 'the check\'s words did not change');
});

group('changing horns on the tuner keeps the concert pitch, and the old rule would not', () => {
  const offOctave = (a, b) => { const c = P.pitchCents(a, b) % 1200; return Math.min(Math.abs(c), 1200 - Math.abs(c)); };
  let positionWouldHaveMoved = false;
  for (const from of INSTRUMENT_KEYS) for (const to of INSTRUMENT_KEYS) {
    const before = P.tuningChecks(from), fresh = P.tuningChecks(to);
    before.forEach((current, index) => {
      const at = P.checkPosition(current, fresh, index);
      ok(offOctave(P.checkSounding(fresh[at]), P.checkSounding(current)) < 1, `${current.choice} on ${from} became ${fresh[at].choice} on ${to}`);
      if (offOctave(P.checkSounding(fresh[Math.min(index, fresh.length - 1)]), P.checkSounding(current)) > 1) positionWouldHaveMoved = true;
    });
  }
  ok(positionWouldHaveMoved, 'the control: keeping the position gets at least one wrong');
  ok(P.checkPosition(check('G4'), [check('G4', 'trumpet')], 0) === 0, 'a chart note keeps its place');
});

// ---------------------------------------------------------------- holding it

group('a note has to be held to count, and a slip takes it back', () => {
  const held = new P.NoteConfirmation();
  for (let i = 1; i < P.NoteConfirmation.readingsNeeded; i++) ok(!held.take({ kind: 'inTune', cents: 2 }), 'not yet');
  ok(!held.isConfirmed, 'one short');
  ok(held.take({ kind: 'inTune', cents: 2 }), 'this one confirms it');
  ok(!held.take({ kind: 'inTune', cents: 2 }), 'and says so once');
  held.take({ kind: 'nothing' }); ok(held.isConfirmed, 'a breath keeps the tick');
  held.take({ kind: 'flat', cents: 30 }); ok(!held.isConfirmed, 'a wrong sound takes it');
  const wobbly = new P.NoteConfirmation();
  for (let i = 1; i < P.NoteConfirmation.readingsNeeded; i++) wobbly.take({ kind: 'inTune', cents: 0 });
  wobbly.take({ kind: 'sharp', cents: 25 });
  for (let i = 1; i < P.NoteConfirmation.readingsNeeded; i++) wobbly.take({ kind: 'inTune', cents: 0 });
  ok(!wobbly.isConfirmed, 'never enough in a row');
  // Six readings from the start of the note, as on iOS.
  const gate = new P.HeldPitch(), conf = new P.NoteConfirmation(), c = check('C5', 'trumpet', 'tuning');
  let at = null;
  for (let r = 1; r <= 10; r++) if (conf.take(P.checkVerdict(c, gate.take(P.checkSounding(c), 0.15)))) at = r;
  ok(at === 6, `confirmed on reading ${at}`);
});

group('a sound is not shown until it has held one note', () => {
  const h = new P.HeldPitch();
  ok(h.take(349.2, 0.15) === null && h.take(349.6, 0.16) === null && h.outcome === 'waiting', 'waiting');
  near(h.take(348.9, 0.15), 349.2, 0.01, 'the third reading shows the middle of three');
  ok(h.take(null, 0.001) === null && h.outcome === 'silence', 'silence ends it');
  ok(h.take(349.2, 0.15) === null, 'and the next note starts from nothing');
  const moving = new P.HeldPitch();
  const shown = [[440, .1], [441, .1], [494, .1], [495, .1], [554, .1], [556, .1]].map(([f, l]) => moving.take(f, l));
  ok(shown.every(s => s === null), 'a tune in two-reading steps is not a note');
});

group('a struck sound that dies away is never shown, however steady', () => {
  const glass = [[393, 0.062], [391, 0.090], [392, 0.031], [392, 0.015], [391, 0.011], [null, 0.005]];
  for (const scale of [1, 0.5, 0.25]) {
    const h = new P.HeldPitch();
    ok(glass.map(([f, l]) => h.take(f, l * scale)).every(s => s === null), `the chime at ${scale}`);
  }
  const blown = new P.HeldPitch();
  ok(glass.slice(0, -1).map(([f]) => blown.take(f, 0.09)).filter(s => s !== null).length === 3, 'the control: the same pitches not dying ARE a note');
});

group('one stray reading keeps a held note, two are a new one', () => {
  const h = new P.HeldPitch();
  [349, 349, 349].forEach(f => h.take(f, 0.15));
  ok(h.take(698, 0.15) === 349, 'the octave error is thrown away');
  near(h.take(350, 0.15), 349, 0.01, 'and the note stays');
  ok(h.take(466, 0.15) === 349, 'one elsewhere is a stray');
  ok(h.take(467, 0.15) === null && h.outcome === 'moved', 'two is a move');
  near(h.take(466, 0.15), 466, 0.01, 'the two that moved count');
});

group('a held note that wanders and swells stays held; a loud attack does not lose it', () => {
  const h = new P.HeldPitch();
  let shown = 0;
  for (let r = 0; r < 40; r++) {
    const cents = 20 * Math.sin(r * 0.9), level = 0.15 * (1 + 0.25 * Math.sin(r * 1.7));
    if (h.take(349.23 * Math.pow(2, cents / 1200), level) !== null) shown++;
  }
  ok(shown === 40 - (P.HeldPitch.readingsNeeded - 1), `shown ${shown}`);
  ok(h.take(349.5, 0.06) !== null && h.take(349.0, 0.15) !== null && h.outcome === 'held', 'air that sags and comes back');
  ok(h.take(345, 0.02) === null && h.outcome === 'died', 'the tail is let go');
  const attack = new P.HeldPitch();
  ok([0.30, 0.22, 0.16, 0.13, 0.13, 0.13].map(l => attack.take(349, l)).filter(s => s !== null).length === 4, 'shown from the third reading with no gap');
});

group('no macOS alert sound can be taken for a note', () => {
  const folders = ['/System/Library/Sounds', '/System/Applications/Mail.app/Contents/Resources'];
  const files = folders.flatMap(f => { try { return fs.readdirSync(f).filter(n => /\.(aiff|wav)$/.test(n)).map(n => path.join(f, n)); } catch { return []; } }).sort();
  let afconvert = true;
  try { execFileSync('which', ['afconvert']); } catch { afconvert = false; }
  if (files.length < 10 || !afconvert) { console.log(`  SKIPPED: [LISTEN] ${files.length} alert sounds and ${afconvert ? 'an' : 'no'} afconvert on this machine, the real sound check did not run`); return; }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'alerts-'));
  let pitchedBefore = 0, shownAfter = 0, runs = 0, longest = 0;
  for (const file of files) {
    const wav = path.join(dir, path.basename(file) + '.wav');
    execFileSync('afconvert', ['-f', 'WAVE', '-d', 'LEF32', '-c', '1', file, wav]);
    const buf = fs.readFileSync(wav);
    let off = 12, rate = 44100, data = null;
    while (off < buf.length) {
      const id = buf.toString('ascii', off, off + 4), size = buf.readUInt32LE(off + 4);
      if (id === 'fmt ') rate = buf.readUInt32LE(off + 12);
      if (id === 'data') { data = new Float32Array(buf.buffer.slice(buf.byteOffset + off + 8, buf.byteOffset + off + 8 + size)); break; }
      off += 8 + size + (size & 1);
    }
    const sound = Float64Array.from(data);
    const block = Math.floor(rate / 10);
    for (let alignment = 0; alignment < 4; alignment++) {
      const samples = new Float64Array(Math.floor(alignment * block / 4) + sound.length);
      samples.set(sound, Math.floor(alignment * block / 4));
      let ring = new Float64Array(0); const h = new P.HeldPitch();
      let shown = 0, pitched = 0, streak = 0;
      for (let from = 0; from < samples.length; from += block) {
        const merged = new Float64Array(ring.length + Math.min(block, samples.length - from));
        merged.set(ring); merged.set(samples.subarray(from, from + block), ring.length);
        ring = merged.length > P.LISTEN_SCOPE_WINDOW ? merged.slice(merged.length - P.LISTEN_SCOPE_WINDOW) : merged;
        if (ring.length < P.LISTEN_WINDOW) continue;
        const frame = P.pitchFrame(ring.subarray(ring.length - P.LISTEN_WINDOW), rate);
        if (frame.frequency !== null) { pitched++; streak++; longest = Math.max(longest, streak); } else streak = 0;
        if (h.take(frame.frequency, frame.level) !== null) shown++;
      }
      runs++; if (pitched) pitchedBefore++; if (shown) shownAfter++;
      ok(shown < P.NoteConfirmation.readingsNeeded, `${path.basename(file)} at alignment ${alignment} was shown for ${shown} readings`);
    }
  }
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(`  [LISTEN] ${files.length} alert sounds, ${runs} runs: the detector gives ${pitchedBefore} a pitch, ${shownAfter} reach the screen, longest pitched streak ${longest}`);
  ok(pitchedBefore > runs / 2, 'the control: most of them have a pitch');
  ok(longest >= P.NoteConfirmation.readingsNeeded, 'and one holds it long enough to matter');
  ok(shownAfter < runs / 10, 'few reach the screen at all');
});

// ---------------------------------------------------------------- the picture

group('the scope starts where the wave goes up through zero, and lies on the target on pitch', () => {
  const f = 349.23, period = RATE / f;
  for (const phase of [0, 0.7, 2.0, 3.1, 4.4, 5.9]) {
    const start = P.risingCrossing(sine(f, phase), RATE, f);
    let expected = (-phase / (2 * Math.PI) * period) % period; if (expected < 0) expected += period;
    const d = Math.abs(start - expected);
    ok(Math.min(d, period - d) < 0.5, `phase ${phase}: ${start} vs ${expected}`);
  }
  const offTarget = trace => trace.reduce((w, v, i) => Math.max(w, Math.abs(v - Math.sin(2 * Math.PI * P.TRACE_CYCLES * i / (trace.length - 1)))), 0);
  const t = P.pitchTrace(sine(277.18, 1.3), RATE, 277.18, 277.18);
  ok(t.length === 240 && offTarget(t) < 0.05, `a sine on pitch lies on the target (${offTarget(t)})`);
  for (const f2 of [123.47, 277.18, 349.23, 698.46]) {
    const tr = P.pitchTrace(brassy(f2), RATE, f2, f2);
    ok(tr.length === 240 && offTarget(tr) < 0.2, `${f2} Hz brassy on pitch (${tr.length ? offTarget(tr) : 'no picture'})`);
  }
  ok(P.pitchTrace(brassy(82.41), RATE, 82.41, 82.41).length === 0, 'one window cannot draw a euphonium\'s low E');
  for (const f3 of [82.41, 87.31, 92.50, 233.08]) {
    const tr = P.pitchTrace(brassy(f3, P.LISTEN_SCOPE_WINDOW), RATE, f3, f3);
    ok(tr.length === 240 && offTarget(tr) < 0.2, `${f3} Hz in the long window`);
  }
});

group('flat falls behind the target and sharp runs ahead, by the arithmetic', () => {
  const target = 277.18;
  const crossings = trace => { const out = []; for (let i = 1; i < trace.length; i++) if (trace[i - 1] < 0 && trace[i] >= 0) out.push((i - 1 + (-trace[i - 1]) / (trace[i] - trace[i - 1])) / (trace.length - 1) * P.TRACE_CYCLES); return out; };
  const flat = target * Math.pow(2, -50 / 1200);
  const fc = crossings(P.pitchTrace(sine(flat, 0.4), RATE, flat, target));
  near(fc[fc.length - 1], 5 * target / flat, 0.03, 'flat');
  ok(fc[fc.length - 1] > 5.1, 'visibly behind');
  const sharp = target * Math.pow(2, 50 / 1200);
  near(crossings(P.pitchTrace(sine(sharp, 0.4), RATE, sharp, target)).find(c => c > 4.5), 5 * target / sharp, 0.03, 'sharp');
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
