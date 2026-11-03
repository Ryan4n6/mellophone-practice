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
const exposed = '\n;({ NOTES, NATURAL_NOTES, SCALES, INSTRUMENTS, fingeringFor, concertKeyFor, scaleDisplayName, verifyFingerings, ' +
  'instrumentNotes, instrumentSelectable, keepsRange, scaleNotesFor, transposedName });';
const ctx = { console, localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} } };
vm.createContext(ctx);
const { NOTES, NATURAL_NOTES, SCALES, INSTRUMENTS, fingeringFor, concertKeyFor, scaleDisplayName, verifyFingerings,
  instrumentNotes, instrumentSelectable, keepsRange, scaleNotesFor, transposedName } = vm.runInContext(script + exposed, ctx);

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

// "Euphonium, Baritone, Valve Trombone Basic Fingering Chart", Mouthpiece
// Express, rendered from the PDF and read off circle by circle on 2026-10-10.
// BASS clef at CONCERT pitch, E2 to Bb4. The euphonium in this app reads treble
// clef a major ninth above that, so each row is checked 14 semitones up.
const publishedEuphoniumAtConcertPitch = {
  "E2":"1+2+3","F2":"1+3","F#2":"2+3","G2":"1+2","Ab2":"1","A2":"2","Bb2":"Open",
  "B2":"1+2+3","C3":"1+3","C#3":"2+3","D3":"1+2","Eb3":"1","E3":"2","F3":"Open",
  "F#3":"2+3","G3":"1+2","Ab3":"1","A3":"2","Bb3":"Open","B3":"1+2","C4":"1",
  "C#4":"2","D4":"Open","Eb4":"1","E4":"2","F4":"Open","F#4":"2+3","G4":"1+2",
  "Ab4":"1","A4":"2","Bb4":"Open"
};
// Worked out here and not by index.html, so the check does not ask the code
// under test for the answer.
function aMajorNinthAbove(name) {
  const letters = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"];
  const raised = letters.indexOf(name.slice(0, -1)) + 12 * Number(name.slice(-1)) + 14;
  return letters[raised % 12] + Math.floor(raised / 12);
}

group('derivation agrees with the stored NOTES table', () => {
  eq(verifyFingerings(), true, 'verifyFingerings()');
  eq(instrumentNotes('mellophone').length, 36, 'the mellophone notes, F#3 to C6 with F3 dropped in #9');
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

group('euphonium matches the published euphonium chart, read a ninth up', () => {
  eq(aMajorNinthAbove('Bb2'), 'C4', 'the helper itself: concert Bb is a treble clef C');
  eq(aMajorNinthAbove('E2'), 'F#3', 'the helper itself: the bottom of the horn');
  eq(Object.keys(publishedEuphoniumAtConcertPitch).length, 31, 'chart rows');
  for (const [n, f] of Object.entries(publishedEuphoniumAtConcertPitch)) {
    eq(fingeringFor(aMajorNinthAbove(n), 'euphonium'), f, `euphonium concert ${n}, written ${aMajorNinthAbove(n)}`);
  }
  // The control: read an octave up instead of a ninth, most of it must disagree.
  const wrong = Object.entries(publishedEuphoniumAtConcertPitch)
    .filter(([n, f]) => fingeringFor(n.slice(0, -1) + (Number(n.slice(-1)) + 1), 'euphonium') !== f).length;
  eq(wrong > 20, true, `read an octave out, ${wrong} of 31 rows disagree`);
});

group('horn differs from the others exactly where it should', () => {
  instrumentNotes('mellophone').forEach(n => eq(fingeringFor(n.name, 'mellophone'), fingeringFor(n.name, 'trumpet'), `${n.name} shared chart`));
  instrumentNotes('mellophone').forEach(n => eq(fingeringFor(n.name, 'euphonium'), fingeringFor(n.name, 'trumpet'), `${n.name} euphonium reads as trumpet`));
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
  Object.keys(INSTRUMENTS).forEach(k => instrumentSelectable(k).forEach(n => {
    checks++;
    if (fingeringFor(n.name, k) === null) { failures++; console.log(`  FAIL ${k} ${n.name} would render "?"`); }
  }));
});

group('concert keys per instrument', () => {
  [['F','Bb','Eb'],['Bb','Eb','Ab'],['C','F','Bb'],['Eb','Ab','Db']].forEach(([w, fInst, tpt]) => {
    eq(concertKeyFor(w, 'mellophone'), fInst, `written ${w} on mellophone`);
    eq(concertKeyFor(w, 'frenchHorn'), fInst, `written ${w} on horn`);
    eq(concertKeyFor(w, 'trumpet'), tpt, `written ${w} on trumpet`);
    eq(concertKeyFor(w, 'euphonium'), tpt, `written ${w} on euphonium`);
  });
});

group('scale names', () => {
  SCALES.forEach(s => {
    eq(scaleDisplayName(s, 'mellophone'), s.name, `mellophone unchanged: ${s.name}`);
    eq(scaleDisplayName(s, 'frenchHorn'), s.name, `horn unchanged: ${s.name}`);
  });
  eq(scaleDisplayName(SCALES.find(s => s.name === 'Concert Bb (Written F)'), 'trumpet'), 'Concert Eb (Written F)', 'trumpet relabel');
  eq(scaleDisplayName(SCALES.find(s => s.name === 'Concert Bb (Written F)'), 'euphonium'), 'Concert Eb (Written F)', 'euphonium relabel');
  eq(scaleDisplayName(SCALES.find(s => s.name === 'Concert Ab (Written Eb)'), 'trumpet'), 'Concert Db (Written Eb)', 'trumpet relabel Eb');
  SCALES.filter(s => !s.name.startsWith('Concert ')).forEach(s => {
    Object.keys(INSTRUMENTS).forEach(k => eq(scaleDisplayName(s, k), s.name, `exercise untouched on ${k}: ${s.name}`));
  });
});

// "4 Valve & 3 Valve BBb Tuba, Euphonium & Sousaphone Basic Fingering Chart",
// Mouthpiece Express (cdn.shopify.com/s/files/1/0968/0109/5812/files/
// fingerings_tuba.pdf), rendered and read circle by circle on 2026-11-03 (#72).
// Bass clef, concert pitch, E1 to F4, the three valve column, every spelling
// it prints. The same table as TubaTests.swift.
const publishedTuba = {
  "E1":"1+2+3","F1":"1+3","F#1":"2+3","Gb1":"2+3","G1":"1+2","G#1":"1","Ab1":"1","A1":"2","A#1":"Open",
  "Bb1":"Open","B1":"1+2+3","C2":"1+3","C#2":"2+3","Db2":"2+3","D2":"1+2","D#2":"1","Eb2":"1","E2":"2",
  "F2":"Open","F#2":"2+3","Gb2":"2+3","G2":"1+2","G#2":"1","Ab2":"1","A2":"2","A#2":"Open","Bb2":"Open",
  "B2":"1+2","C3":"1","C#3":"2","Db3":"2","D3":"Open","D#3":"1","Eb3":"1","E3":"2","F3":"Open","F#3":"2+3",
  "Gb3":"2+3","G3":"1+2","G#3":"1","Ab3":"1","A3":"2","A#3":"Open","Bb3":"Open","B3":"1+2","C4":"1",
  "C#4":"2","Db4":"2","D4":"Open","D#4":"1","Eb4":"1","E4":"2","F4":"Open"
};
const midiOf = name => ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
  .indexOf({ "Db": "C#", "D#": "Eb", "Gb": "F#", "G#": "Ab", "A#": "Bb" }[name.slice(0, -1)] || name.slice(0, -1)) + 12 * (Number(name.slice(-1)) + 1);

group('the tuba matches the published tuba chart (#72)', () => {
  eq(Object.keys(publishedTuba).length, 53, 'chart rows');
  for (const [n, f] of Object.entries(publishedTuba)) eq(fingeringFor(n, 'tuba'), f, `tuba ${n}`);
  // The control: a semitone out, most of it must disagree. (An octave out is
  // no control on a tuba, whose series repeats by octaves.)
  const names = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"];
  const wrong = Object.entries(publishedTuba).filter(([n, f]) => {
    const up = midiOf(n) + 1;
    return fingeringFor(names[up % 12] + (Math.floor(up / 12) - 1), 'tuba') !== f;
  }).length;
  eq(wrong > 45, true, `read a semitone out, ${wrong} of 53 rows disagree`);
  const checked = new Set(Object.keys(publishedTuba).map(midiOf));
  instrumentNotes('tuba').forEach(n => eq(checked.has(midiOf(n.name)), true, `tuba ${n.name} is on the chart`));
});

group('the bass clef euphonium matches the euphonium chart as printed (#72)', () => {
  for (const [n, f] of Object.entries(publishedEuphoniumAtConcertPitch)) eq(fingeringFor(n, 'euphoniumBass'), f, `euphonium B.C. ${n}`);
  const checked = new Set(Object.keys(publishedEuphoniumAtConcertPitch).map(midiOf));
  instrumentNotes('euphoniumBass').forEach(n => eq(checked.has(midiOf(n.name)), true, `euphonium B.C. ${n.name} is on the chart`));
});

group('each horn is shown its own notes (#72)', () => {
  eq(NOTES.length, 66, 'the table, E1 to C6 with both spellings where it has them');
  const before = ["F#3","G3","Ab3","A3","Bb3","B3","C4","C#4","D4","Eb4","E4","F4","F#4","G4","Ab4","A4","Bb4","B4",
    "C5","C#5","D5","Eb5","E5","F5","F#5","G5","Ab5","A5","Bb5","B5","C6"].join();
  ['mellophone', 'frenchHorn', 'trumpet', 'euphonium'].forEach(k => {
    eq(instrumentSelectable(k).map(n => n.name).join(), before, `${k} is shown what it was before the tuba`);
    eq(instrumentNotes(k).length, 36, `${k}, both spellings`);
    eq(INSTRUMENTS[k].clef, 'treble', `${k} clef`);
  });
  eq(instrumentSelectable('tuba')[0].name + ' ' + instrumentSelectable('tuba').slice(-1)[0].name, 'E1 F4', 'tuba span');
  eq(instrumentSelectable('euphoniumBass')[0].name + ' ' + instrumentSelectable('euphoniumBass').slice(-1)[0].name, 'E2 Bb4', 'euphonium B.C. span');
  eq(INSTRUMENTS.tuba.clef + INSTRUMENTS.euphoniumBass.clef, 'bassbass', 'bass clefs');
  eq(INSTRUMENTS.tuba.defaultRange.join(), 'Bb1,F3', 'tuba working range');
  eq(keepsRange('C2', 'C3', 'tuba'), true, 'a tuba range on a tuba');
  eq(keepsRange('C4', 'G5', 'tuba'), false, 'a mellophone range on a tuba');
  eq(keepsRange('Bb1', 'F3', 'mellophone'), false, 'a tuba range on a mellophone');
  eq(fingeringFor('C4', 'mellophone'), 'Open', 'C4 is still open on a mellophone');
  eq(NOTES.filter(n => n.finger === '').every(n => fingeringFor(n.name, 'mellophone') === null), true, 'every "" row is one a mellophone cannot play');
});

group('every exercise on every horn, on its own page (#72)', () => {
  Object.keys(INSTRUMENTS).forEach(k => {
    const span = new Set(instrumentNotes(k).map(n => n.name));
    SCALES.forEach(s => {
      const notes = scaleNotesFor(s, k);
      eq(notes.length, s.notes.length, `${s.name} on ${k} resolves`);
      notes.forEach(n => eq(span.has(n.name), true, `${s.name} on ${k}: ${n.name} in span`));
    });
  });
  const slur = SCALES.find(s => s.name === 'Lip Slurs (Open)');
  eq(scaleNotesFor(slur, 'tuba').map(n => n.name).join(), 'Bb1,F2,Bb2,D3,F3,D3,Bb2,F2,Bb1', 'the tuba lip slur is its open series');
  eq(scaleNotesFor(slur, 'mellophone').map(n => n.name).join(), slur.notes.join(), 'the mellophone lip slur is untouched');
  SCALES.filter(s => s.hold).forEach(s => ['tuba', 'euphoniumBass'].forEach(k => scaleNotesFor(s, k).forEach(n => {
    const drop = ["Open","2","1","1+2","2+3","1+3","1+2+3"].indexOf(s.hold);
    eq(INSTRUMENTS[k].openPartials.some(p => midiOf(p) - drop === midiOf(n.name)), true, `${s.name} on ${k}: ${n.name} on the ${s.hold} series`);
  })));
  eq(transposedName('C4', -26, -15), 'Bb1', 'C4 down a tone and two octaves');
  eq(transposedName('F#4', -26, -15), 'E2', 'spelled by the interval');
  eq(transposedName('Bb2', 0, 0), 'Bb2', 'no move');
  const bb = SCALES.find(s => s.name === 'Concert Bb (Written F)');
  eq(scaleDisplayName(bb, 'tuba'), 'Concert Eb', 'a concert pitch horn shows no written half');
  eq(scaleDisplayName(bb, 'euphoniumBass'), 'Concert Eb', 'nor the bass clef euphonium');
  eq(scaleNotesFor(bb, 'tuba').map(n => n.name).join(), 'Eb2,F2,G2,Ab2,Bb2,C3,D3,Eb3', 'the same scale a trumpet plays, on the tuba page');
  ['tuba', 'euphoniumBass'].forEach(k => INSTRUMENTS[k].tuningNotes.forEach(tn => {
    eq(fingeringFor(tn.written, k), 'Open', `${k} tunes on an open ${tn.written}`);
    eq(tn.written.slice(0, -1), tn.concert, `${k} ${tn.written} is concert ${tn.concert}`);
  }));
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
