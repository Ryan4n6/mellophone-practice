// scripts/check-instruments.js
//
// The web version's answer to ios/MellophoneTests/InstrumentTests.swift: it runs
// the derivation OUT OF index.html against the same published charts. Node only,
// no DOM needed, because every function under test is pure. Nothing here ships;
// index.html still loads nothing and needs no build.
//
//     node scripts/check-instruments.js
//
// Run it after touching NOTES, SCALES, INSTRUMENTS or fingeringFor.
const fs = require('fs');
const vm = require('vm');

const html = fs.readFileSync(require('path').join(__dirname, '..', 'index.html'), 'utf8');
const script = html.split('<script>')[1].split('</script>')[0].replace(/\ninit\(\);\n/, '\n');

// `const` at the top level of a script does not attach to the context object,
// so ask the script itself for the bindings under test.
const exposed = '\n;({ NOTES, NATURAL_NOTES, SCALES, INSTRUMENTS, fingeringFor, concertKeyFor, scaleDisplayName, verifyFingerings });';
const ctx = { console, localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} } };
vm.createContext(ctx);
const { NOTES, NATURAL_NOTES, SCALES, INSTRUMENTS, fingeringFor, concertKeyFor, scaleDisplayName, verifyFingerings } =
  vm.runInContext(script + exposed, ctx);

let failures = 0, checks = 0;
function eq(actual, expected, what) {
  checks++;
  if (actual !== expected) { failures++; console.log(`  FAIL ${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`); }
}
function group(name, fn) { console.log(name); fn(); }

// Michael Droste / TrumpetStudio.com, transcribed from the chart.
const publishedTrumpet = {
  "F#3":"1+2+3","G3":"1+3","Ab3":"2+3","A3":"1+2","Bb3":"1","B3":"2",
  "C4":"Open","C#4":"1+2+3","D4":"1+3","Eb4":"2+3","E4":"1+2","F4":"1",
  "F#4":"2","G4":"Open","Ab4":"2+3","A4":"1+2","Bb4":"1","B4":"2",
  "C5":"Open","C#5":"1+2"
};
// "Single F Horn Fingerings", Stewart Schlazer. Written pitch. Its D5 is given
// as "0 or 1"; the chart fingering here is the open one.
const publishedHorn = {
  "F#3":"2","Gb3":"2","G3":"Open","Ab3":"2+3","A3":"1+2","Bb3":"1","B3":"2",
  "C4":"Open","C#4":"1+2","Db4":"1+2","D4":"1","Eb4":"2","E4":"Open","F4":"1",
  "F#4":"2","Gb4":"2","G4":"Open","Ab4":"2+3","A4":"1+2","Bb4":"1","B4":"2",
  "C5":"Open","C#5":"2","Db5":"2","D5":"Open","Eb5":"2","E5":"Open","F5":"1"
};

group('derivation agrees with the stored NOTES table', () => {
  eq(verifyFingerings(), true, 'verifyFingerings()');
  eq(NOTES.length, 36, 'note count, F#3 to C6 with F3 dropped in #9');
});

group('mellophone and trumpet match the published trumpet chart', () => {
  for (const [n, f] of Object.entries(publishedTrumpet)) {
    eq(fingeringFor(n, 'mellophone'), f, `mellophone ${n}`);
    eq(fingeringFor(n, 'trumpet'), f, `trumpet ${n}`);
  }
});

group('french horn matches the published single F horn chart', () => {
  for (const [n, f] of Object.entries(publishedHorn)) eq(fingeringFor(n, 'frenchHorn'), f, `horn ${n}`);
});

group('horn differs from the others exactly where it should', () => {
  NOTES.forEach(n => eq(fingeringFor(n.name, 'mellophone'), fingeringFor(n.name, 'trumpet'), `${n.name} shared chart`));
  eq(fingeringFor('E4', 'frenchHorn'), 'Open', 'horn E4');
  eq(fingeringFor('E4', 'mellophone'), '1+2', 'mello E4');
  eq(fingeringFor('D5', 'frenchHorn'), 'Open', 'horn D5');
  eq(fingeringFor('D5', 'mellophone'), '1', 'mello D5');
  eq(fingeringFor('G3', 'frenchHorn'), 'Open', 'horn G3');
  eq(fingeringFor('G3', 'mellophone'), '1+3', 'mello G3');
});

group('F3 is playable on a horn and on nothing else here', () => {
  eq(fingeringFor('F3', 'mellophone'), null, 'mello F3');
  eq(fingeringFor('F3', 'trumpet'), null, 'trumpet F3');
  eq(fingeringFor('F3', 'frenchHorn'), '1', 'horn F3');
});

group('every chart row renders a real fingering on every instrument', () => {
  Object.keys(INSTRUMENTS).forEach(k => NATURAL_NOTES.forEach(n => {
    checks++;
    if (fingeringFor(n.name, k) === null) { failures++; console.log(`  FAIL ${k} ${n.name} would render "?"`); }
  }));
});

group('concert keys per instrument', () => {
  [['F','Bb','Eb'],['Bb','Eb','Ab'],['C','F','Bb'],['Eb','Ab','Db']].forEach(([w, fInst, tpt]) => {
    eq(concertKeyFor(w, 'mellophone'), fInst, `written ${w} on mellophone`);
    eq(concertKeyFor(w, 'frenchHorn'), fInst, `written ${w} on horn`);
    eq(concertKeyFor(w, 'trumpet'), tpt, `written ${w} on trumpet`);
  });
});

group('scale names', () => {
  SCALES.forEach(s => {
    eq(scaleDisplayName(s, 'mellophone'), s.name, `mellophone unchanged: ${s.name}`);
    eq(scaleDisplayName(s, 'frenchHorn'), s.name, `horn unchanged: ${s.name}`);
  });
  eq(scaleDisplayName(SCALES.find(s => s.name === 'Concert Bb (Written F)'), 'trumpet'), 'Concert Eb (Written F)', 'trumpet relabel');
  eq(scaleDisplayName(SCALES.find(s => s.name === 'Concert Ab (Written Eb)'), 'trumpet'), 'Concert Db (Written Eb)', 'trumpet relabel Eb');
  SCALES.filter(s => !s.name.startsWith('Concert ')).forEach(s => {
    Object.keys(INSTRUMENTS).forEach(k => eq(scaleDisplayName(s, k), s.name, `exercise untouched on ${k}: ${s.name}`));
  });
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
