// scripts/check-glyphs.js
//
// The horn drawings on the website are the iOS app's (#79). `HORN_DRAWINGS`
// in index.html is the same list of parts as `BrassGlyph.drawing(for:)` in
// ios/Mellophone/Views/BrassGlyph.swift, number for number, and each horn
// draws the picture `Instrument.glyph` gives it in InstrumentChip.swift. The
// Swift is read here as text, so a drawing changed on one side and not the
// other fails this rather than shipping two different horns.
//
//     node scripts/check-glyphs.js
//
// Run it after touching a drawing on either side. A drawing is LOOKED at too:
// the numbers matching says the web draws what the phone draws, not that
// what the phone draws looks like a horn (#75, #76).
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const script = html.split('<script>')[1].split('</script>')[0].replace(/\ninit\(\);\n/, '\n');
const exposed = '\n;({ INSTRUMENTS, HORN_DRAWINGS: typeof HORN_DRAWINGS === "undefined" ? null : HORN_DRAWINGS, ' +
  'hornSVG: typeof hornSVG === "undefined" ? null : hornSVG });';
const ctx = { console: { ...console, info() {} }, localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} } };
vm.createContext(ctx);
const { INSTRUMENTS, HORN_DRAWINGS, hornSVG } = vm.runInContext(script + exposed, ctx);

let failures = 0, checks = 0;
function ok(cond, what, detail) {
  checks++;
  if (!cond) { failures++; console.log(`  FAIL ${what}${detail !== undefined ? `: ${detail}` : ''}`); }
}
function group(name, fn) { console.log(name); fn(); }

// ---- the Swift, read as text ----------------------------------------------

const swift = fs.readFileSync(path.join(root, 'ios/Mellophone/Views/BrassGlyph.swift'), 'utf8')
  .replace(/\/\/.*$/gm, '');
const chip = fs.readFileSync(path.join(root, 'ios/Mellophone/Views/InstrumentChip.swift'), 'utf8')
  .replace(/\/\/.*$/gm, '');

// The body of each `case .kind:` in one function: from the function's name to
// its closing brace at four spaces, cut at every case.
function caseBodies(source, fnName) {
  const start = source.indexOf(fnName);
  if (start < 0) throw new Error(`no ${fnName} in the Swift`);
  const fn = source.slice(start, source.indexOf('\n    }\n', start));
  const out = {};
  const pieces = fn.split(/\n\s*case (\.[\w]+(?:, \.[\w]+)*):/);
  for (let i = 1; i < pieces.length; i += 2) {
    for (const name of pieces[i].split(',')) out[name.trim().slice(1)] = pieces[i + 1];
  }
  return out;
}

// A Swift part call flattened to its name and every number (and nil) in order.
const PART_NAMES = ['tube', 'block', 'bell', 'oval', 'ring', 'curve'];
function swiftParts(body) {
  const parts = [];
  const re = new RegExp(`\\b(${PART_NAMES.join('|')})\\(`, 'g');
  for (let m; (m = re.exec(body));) {
    let depth = 1, i = m.index + m[0].length;
    for (; i < body.length && depth; i++) {
      if (body[i] === '(' || body[i] === '[') depth++;
      else if (body[i] === ')' || body[i] === ']') depth--;
    }
    const args = body.slice(m.index + m[0].length, i - 1);
    const tokens = (args.match(/-?\d+(?:\.\d+)?|\bnil\b/g) || []).map(t => t === 'nil' ? null : Number(t));
    parts.push([m[1], ...tokens]);
    re.lastIndex = i;
  }
  return parts;
}
// The same flattening for a web part, so the two can be compared as lists.
function flat(v) { return Array.isArray(v) ? v.flatMap(flat) : [v]; }
function webParts(drawing) { return drawing.parts.map(([name, ...args]) => [name, ...flat(args)]); }

const swiftKinds = (swift.match(/enum Kind: CaseIterable \{\s*case ([^\n]+)/) || [])[1]
  .split(',').map(s => s.trim());
const swiftDrawings = caseBodies(swift, 'private static func drawing(for kind: Kind)');
const swiftBoxes = {};
for (const [k, body] of Object.entries(caseBodies(swift, 'static func box(for kind: Kind)'))) {
  const m = body.match(/CGSize\(width: ([\d.]+), height: ([\d.]+)\)/);
  swiftBoxes[k] = [Number(m[1]), Number(m[2])];
}
const swiftGlyphOf = caseBodies(chip, 'var glyph: BrassGlyph.Kind');
const swiftHornGlyph = {};
for (const [horn, body] of Object.entries(swiftGlyphOf)) swiftHornGlyph[horn] = (body.match(/return \.(\w+)/) || [])[1];

group('The drawings exist', () => {
  ok(HORN_DRAWINGS !== null, 'index.html has HORN_DRAWINGS');
  ok(typeof hornSVG === 'function', 'index.html has hornSVG()');
});
if (!HORN_DRAWINGS || typeof hornSVG !== 'function') {
  console.log(`\n${checks - failures}/${checks} checks passed`);
  process.exit(1);
}

group('The same horns as BrassGlyph.Kind', () => {
  ok(swiftKinds.length === 5, 'the Swift has five drawings', swiftKinds.join(', '));
  ok(JSON.stringify(Object.keys(HORN_DRAWINGS).sort()) === JSON.stringify([...swiftKinds].sort()),
    'the web has one drawing per Swift Kind and no other', Object.keys(HORN_DRAWINGS).join(', '));
});

group('Number for number the Swift drawing', () => {
  for (const kind of swiftKinds) {
    const web = HORN_DRAWINGS[kind];
    if (!web) continue;
    ok(JSON.stringify(web.box) === JSON.stringify(swiftBoxes[kind]), `${kind}: box`,
      `web ${JSON.stringify(web.box)}, Swift ${JSON.stringify(swiftBoxes[kind])}`);
    const s = swiftParts(swiftDrawings[kind] || '');
    const w = webParts(web);
    ok(s.length > 0 && w.length === s.length, `${kind}: ${s.length} parts`, `web has ${w.length}`);
    s.forEach((part, i) => ok(JSON.stringify(w[i]) === JSON.stringify(part), `${kind}: part ${i + 1} (${part[0]})`,
      `web ${JSON.stringify(w[i])}, Swift ${JSON.stringify(part)}`));
  }
});

group('Each horn draws the picture the iOS chip gives it', () => {
  ok(Object.keys(swiftHornGlyph).length === 6, 'the Swift maps six horns', JSON.stringify(swiftHornGlyph));
  for (const [key, inst] of Object.entries(INSTRUMENTS)) {
    ok(inst.glyph === swiftHornGlyph[key], `${key} draws as ${swiftHornGlyph[key]}`, inst.glyph);
  }
  // Only the euphonium shares, being one horn in two clefs; anything else
  // sharing a picture is what the picture is there to prevent.
  const byGlyph = {};
  for (const [key, inst] of Object.entries(INSTRUMENTS)) (byGlyph[inst.glyph] = byGlyph[inst.glyph] || []).push(key);
  for (const [g, keys] of Object.entries(byGlyph)) {
    ok(keys.length === 1 || (g === 'euphonium' && keys.sort().join() === 'euphonium,euphoniumBass'),
      `only the euphonium shares a drawing`, `${g}: ${keys.join(', ')}`);
  }
});

group('No two drawings are the same', () => {
  const seen = new Map();
  for (const [kind, d] of Object.entries(HORN_DRAWINGS)) {
    const key = JSON.stringify(d.parts);
    ok(!seen.has(key), `${kind} is not a copy of ${seen.get(key)}`);
    seen.set(key, kind);
  }
});

group('hornSVG draws every part, in its own box', () => {
  for (const [kind, d] of Object.entries(HORN_DRAWINGS)) {
    const svg = hornSVG(kind);
    ok(svg.includes(`viewBox="0 0 ${d.box[0]} ${d.box[1]}"`), `${kind}: viewBox is the box`);
    // Each part its own element: laid into one path, two parts wound opposite
    // ways cut a hole where they cross (the same reason the Swift fills each).
    const elements = (svg.match(/<(polyline|path|ellipse|rect)\b/g) || []).length;
    ok(elements === d.parts.length, `${kind}: one element per part`, `${elements} for ${d.parts.length}`);
    ok(/aria-hidden="true"/.test(svg), `${kind}: hidden from a screen reader, the name says it`);
    ok(!/https?:/.test(svg.replace('http://www.w3.org/2000/svg', '')), `${kind}: nothing to fetch`);
  }
  ok(hornSVG('nonsense') === '', 'an unknown drawing draws nothing rather than throwing');
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
