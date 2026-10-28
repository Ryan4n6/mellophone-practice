// scripts/check-language.js
//
// The web app in Spanish and French (#68), held to the iOS app's (#67).
//
//     node scripts/check-language.js
//
// - Note names: the one rule that turns "Bb4" into what a reader reads, the
//   same cases as ios/MellophoneTests/LanguageTests.swift. Spanish counts
//   middle C as Do4, French as Do3.
// - The drill's typed answers read back to the stored name, Do Re Mi too.
// - Every key the page asks for (its t() calls, its markup's words and
//   attributes, and the instrument and scale data it translates) is in both
//   languages, with the same %@ and %lld arguments and no dashes, and nothing
//   is in the table that the page no longer asks for.
// - Every key the page shares with the iOS string catalog has the catalog's
//   translation, plurals included: a word changed on one side is caught here.
// - t() itself: plurals, reordered arguments, the English fallback.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
const page = html.split('<script>')[1].split('</script>')[0].replace(/\ninit\(\);\n/, '\n');
const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, 'ios/Mellophone/Resources/Localizable.xcstrings'), 'utf8')).strings;
const warnings = [];
const ctx = {
  console: { log() {}, info() {}, error() {}, debug() {}, warn: m => warnings.push(m) },
  localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
  Intl,
};
vm.createContext(ctx);
vm.runInContext(page, ctx);
const run = code => vm.runInContext(code, ctx);
const { STRINGS, PLURALS_EN, INSTRUMENTS, SCALES } = run('({ STRINGS, PLURALS_EN, INSTRUMENTS, SCALES })');

let passed = 0, failed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; return; }
  failed++;
  console.log(`  FAIL  ${name}${detail ? `\n        ${detail}` : ''}`);
}
const same = (name, got, want) => check(name, JSON.stringify(got) === JSON.stringify(want), `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

console.log('note names');
const show = (name, naming) => run(`showNote(${JSON.stringify(name)}, ${JSON.stringify(naming)})`);
for (const n of ['C4', 'Bb4', 'F#3', 'C6']) same(`letters keep ${n}`, show(n, 'letters'), n);
same('Spanish C4 is Do4', show('C4', 'solfege'), 'Do4');
same('Spanish Bb4', show('Bb4', 'solfege'), 'Si♭4');
same('Spanish F#3', show('F#3', 'solfege'), 'Fa♯3');
same('Spanish D5', show('D5', 'solfege'), 'Re5');
same('French C4 is Do3', show('C4', 'solfegeFrench'), 'Do3');
same('French C5 is Do4', show('C5', 'solfegeFrench'), 'Do4');
same('French D5', show('D5', 'solfegeFrench'), 'Ré4');
same('French Bb3', show('Bb3', 'solfegeFrench'), 'Si♭2');
same('a key has no octave', show('Eb', 'solfegeFrench'), 'Mi♭');
for (const other of ['Open', '1+2', '?', ' ', '']) same(`not a note: ${JSON.stringify(other)}`, show(other, 'solfege'), other);
const notes = run('NOTES.map(n => n.name)');
for (const naming of ['letters', 'solfege', 'solfegeFrench']) {
  const shown = notes.map(n => show(n, naming));
  check(`no two of the ${notes.length} notes share a name in ${naming}`, new Set(shown).size === notes.length);
}
same('a Spanish browser defaults to Do Re Mi', run("defaultNaming('es')"), 'solfege');
same('a French browser to the French count', run("defaultNaming('fr')"), 'solfegeFrench');
same('English to letters', run("defaultNaming('en')"), 'letters');
same('es-MX is Spanish', run("languageFrom(['es-MX', 'en-US'])"), 'es');
same('a language the page does not speak is English', run("languageFrom(['de-DE'])"), 'en');

console.log('typed answers');
const parse = (text, naming) => run(`parseNoteAnswer(${JSON.stringify(text)}, ${JSON.stringify(naming)})`);
same('Bb4', parse('Bb4', 'letters'), 'Bb4');
same('bb4, lower case', parse('bb4', 'letters'), 'Bb4');
same('c#5', parse('c#5', 'letters'), 'C#5');
same('Spanish Si♭4', parse('Si♭4', 'solfege'), 'Bb4');
same('Spanish sib4', parse('sib4', 'solfege'), 'Bb4');
same('Spanish sol4', parse('sol4', 'solfege'), 'G4');
same('French sib3 is written Bb4', parse('sib3', 'solfegeFrench'), 'Bb4');
same('French Ré4 is written D5', parse('Ré4', 'solfegeFrench'), 'D5');
same('French re4 without the accent', parse('re4', 'solfegeFrench'), 'D5');
same('letters still work in French', parse('C5', 'solfegeFrench'), 'C5');
same('junk', parse('hello', 'solfege'), null);
same('every shown name reads back', notes.every(n => ['letters', 'solfege', 'solfegeFrench'].every(m => parse(show(n, m), m) === n)), true);

console.log('the table');
// Every key the page asks for, the way the page itself finds them.
const asked = new Set();
for (const m of page.matchAll(/\bt\(\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")/g)) asked.add(vm.runInNewContext(m[1]));
const body = html.slice(html.indexOf('<body'), html.indexOf('<script')).replace(/<svg[\s\S]*?<\/svg>/g, '');
const decode = s => s.replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&minus;/g, '−').replace(/&amp;/g, '&').replace(/&middot;/g, '·').replace(/&nbsp;/g, ' ');
for (const m of body.matchAll(/>([^<]+)</g)) { const p = run(`markupText(${JSON.stringify(decode(m[1]))})`); if (p) asked.add(p.key); }
for (const m of body.matchAll(/(?:aria-label|title|placeholder)="([^"]*)"/g)) asked.add(decode(m[1]));
for (const inst of Object.values(INSTRUMENTS)) for (const k of ['displayName', 'shortName', 'inSentence', 'caveat']) if (inst[k]) asked.add(inst[k]);
for (const s of SCALES) { if (!/^Concert \S+ \(Written \S+\)$/.test(s.name)) asked.add(s.name); asked.add(s.desc); }
// Words that are the same in every language, or that the script overwrites.
const UNTRANSLATED = new Set(['C5', 'Hz', 'Largo', 'Andante', 'Allegro', 'Vivace']);
const args = text => {
  const found = [...text.matchAll(/%(?:(\d+)\$)?(@|lld)/g)];
  if (found.length && found.every(f => f[1])) return found.sort((a, b) => a[1] - b[1]).map(f => f[2]).join();
  return found.map(f => f[2]).join();
};
const forms = v => typeof v === 'string' ? [v] : [v.one, v.other];
// Built from char codes so this file holds no dash itself.
const DASHES = new RegExp('[' + String.fromCharCode(0x2013, 0x2014) + ']');
for (const lang of ['es', 'fr']) {
  const table = STRINGS[lang];
  const missing = [...asked].filter(k => !UNTRANSLATED.has(k) && !(k in table));
  check(`${lang}: every key the page asks for is translated`, missing.length === 0, missing.slice(0, 5).map(k => JSON.stringify(k)).join(', '));
  const stale = Object.keys(table).filter(k => !asked.has(k));
  check(`${lang}: nothing in the table the page no longer asks for`, stale.length === 0, stale.slice(0, 5).map(k => JSON.stringify(k)).join(', '));
  const badArgs = Object.entries(table).filter(([k, v]) => forms(v).some(f => args(f) !== args(k)));
  check(`${lang}: every translation keeps its arguments`, badArgs.length === 0, badArgs.slice(0, 3).map(([k, v]) => `${k} -> ${JSON.stringify(v)}`).join('; '));
  const dashed = Object.values(table).flatMap(forms).filter(f => DASHES.test(f));
  check(`${lang}: no dashes`, dashed.length === 0, dashed.slice(0, 3).join('; '));
}
// Held to the iOS catalog.
const fromCatalog = (entry, lang) => {
  const l = entry.localizations && entry.localizations[lang];
  if (!l) return undefined;
  if (l.stringUnit) return l.stringUnit.value;
  const p = l.variations && l.variations.plural;
  return p ? { one: p.one.stringUnit.value, other: p.other.stringUnit.value } : undefined;
};
let shared = 0;
for (const lang of ['es', 'fr']) {
  const drift = [];
  for (const [k, v] of Object.entries(STRINGS[lang])) {
    if (!catalog[k]) continue;
    shared++;
    if (JSON.stringify(fromCatalog(catalog[k], lang)) !== JSON.stringify(v)) drift.push(`${k}: web ${JSON.stringify(v)}, iOS ${JSON.stringify(fromCatalog(catalog[k], lang))}`);
  }
  check(`${lang}: every key shared with iOS has the catalog's translation`, drift.length === 0, drift.slice(0, 3).join('\n        '));
}
const pluralDrift = Object.entries(PLURALS_EN).filter(([k, v]) => JSON.stringify(fromCatalog(catalog[k] || {}, 'en')) !== JSON.stringify(v));
check('English plurals are the catalog\'s', pluralDrift.length === 0, pluralDrift.map(([k]) => k).join(', '));
const needPlural = [...asked].filter(k => /%lld/.test(k) && catalog[k] && fromCatalog(catalog[k], 'en') && !(k in PLURALS_EN));
check('every English plural the page uses is in PLURALS_EN', needPlural.length === 0, needPlural.join(', '));

console.log('t()');
same('English plural, one', run("t('%lld cents low', 1)"), '1 cent low');
same('English plural, other', run("t('%lld cents low', 12)"), '12 cents low');
same('an English key with no plural is itself', run("t('That\\'s %@', 'C5')"), "That's C5");
run("LANGUAGE = 'es'");
same('Spanish plural, one', run("t('%lld cents low', 1)"), '1 cent por debajo');
same('Spanish plural, other', run("t('%lld cents low', 12)"), '12 cents por debajo');
same('Spanish words', run("t('Open')"), 'Al aire');
run("LANGUAGE = 'fr'");
same('French zero takes the singular', run("t('%lld bars', 0)"), '0 mesure');
same('French reordered arguments', run("t('%@ is %@. Aim higher.', 'Do4', 'À vide')"), 'Do4, c\'est À vide. Vise plus haut.');
same('French tuning line', run("t('%@ on your %@ is written %@.', t('Concert %@', 'Fa'), t('mello'), 'Do4')"), 'Fa réel sur ton mellophone s\'écrit Do4.');
same('French note check', run("noteNaming = 'solfegeFrench'; checkWords(makeCheck('C5', 523.25, 'mellophone'), { kind: 'wrongNote', writtenName: 'G4', sameValves: true, tooHigh: false }, false).headline"), "C'est Sol3");
same('French scale name', run("scaleDisplayName(SCALES[0], 'trumpet')"), 'Mi♭ réel (écrit Fa)');
warnings.length = 0;
same('a key with no translation shows its English', run("t('Not a key in any table')"), 'Not a key in any table');
check('and says so in the console', warnings.some(w => /\[LOCALE\] no fr/.test(w)), warnings.join(' | '));
run("LANGUAGE = 'en'; noteNaming = 'letters'");
same('English note check is unchanged', run("checkWords(makeCheck('C5', 523.25, 'mellophone'), { kind: 'inTune', cents: 2 }, true).detail"), 'C5, Open');

console.log(`\n${passed}/${passed + failed} checks passed (${asked.size} keys asked for, ${shared / 2} shared with iOS)`);
process.exit(failed ? 1 : 0);
