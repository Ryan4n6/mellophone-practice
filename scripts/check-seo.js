// scripts/check-seo.js
//
// Can a search engine, an AI search tool or a group chat tell what this page
// is (#83)? Until 2026-11-03 the head said "Honk It Up!" and nothing else,
// and a search for the app by name found nothing of ours.
//
//     node scripts/check-seo.js
//
// Reads index.html's head and the files beside it as text. Run it after
// touching the head, the preview image or the sitemap. It also holds the
// page to its oldest rule while the head grows: nothing here may make the
// page itself load anything from the network.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const head = html.slice(0, html.indexOf('</head>'));

const URL_LIVE = 'https://ryan4n6.github.io/mellophone-practice/';
const APP_STORE = 'https://apps.apple.com/us/app/honk-it-up/id6802899812';
// Built from code points so this file holds none of the characters it bans.
const DASHES = new RegExp('[' + String.fromCharCode(0x2013, 0x2014) + ']');

let failures = 0, checks = 0;
function ok(cond, what, detail) {
  checks++;
  if (!cond) { failures++; console.log(`  FAIL ${what}${detail !== undefined ? `: ${detail}` : ''}`); }
}
function group(name, fn) { console.log(name); fn(); }

const attr = (tag, name) => { const m = tag.match(new RegExp(`\\b${name}="([^"]*)"`)); return m ? m[1] : null; };
const metas = [...head.matchAll(/<meta\b[^>]*>/g)].map(m => m[0]);
const meta = (key, value) => {
  const tag = metas.find(t => attr(t, key) === value);
  return tag ? attr(tag, 'content') : null;
};
const link = rel => { const t = (head.match(new RegExp(`<link\\b[^>]*rel="${rel}"[^>]*>`)) || [])[0]; return t ? attr(t, 'href') : null; };
const decode = s => s && s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'");

// A PNG's size is in its IHDR chunk, bytes 16 to 24.
function pngSize(file) {
  const b = fs.readFileSync(file);
  return b.slice(1, 4).toString() === 'PNG' ? [b.readUInt32BE(16), b.readUInt32BE(20)] : null;
}

group('Title and description', () => {
  const title = decode((head.match(/<title>([^<]*)<\/title>/) || [])[1]);
  ok(!!title && title.startsWith('Honk It Up!'), 'the title starts with the app name', title);
  ok(!!title && /mellophone/i.test(title) && /tuba/i.test(title), 'and says which horns', title);
  // Google shows about 60 to 70 characters before it cuts.
  ok(!!title && title.length <= 70, 'and fits a results line', title && title.length);
  const d = decode(meta('name', 'description'));
  ok(!!d && d.length >= 70 && d.length <= 160, 'a description of 70 to 160 characters', d && d.length);
  ok(!!d && /free/i.test(d) && /offline/i.test(d) && /fingering/i.test(d), 'that says free, offline and fingering charts', d);
  const k = meta('name', 'keywords');
  ok(!!k && /mellophone fingering chart/.test(k) && /tuba/.test(k), 'keywords name the charts people search for', k);
  ok(meta('name', 'robots') === 'index, follow', 'robots: index, follow', meta('name', 'robots'));
  ok(link('canonical') === URL_LIVE, 'one canonical address, the live one', link('canonical'));
  // The name on a home screen stays short; only the results line is long.
  ok(meta('name', 'apple-mobile-web-app-title') === 'Honk It Up!', 'the home screen name is still Honk It Up!');
});

group('A link preview', () => {
  ok(meta('property', 'og:type') === 'website', 'og:type website');
  ok(meta('property', 'og:url') === URL_LIVE, 'og:url is the canonical address', meta('property', 'og:url'));
  ok(!!meta('property', 'og:title') && meta('property', 'og:title').startsWith('Honk It Up!'), 'og:title');
  ok(!!meta('property', 'og:description'), 'og:description');
  ok(meta('property', 'og:site_name') === 'Honk It Up!', 'og:site_name');
  ok(meta('property', 'og:locale') === 'en_US', 'og:locale en_US');
  const alts = metas.filter(t => attr(t, 'property') === 'og:locale:alternate').map(t => attr(t, 'content')).sort();
  ok(JSON.stringify(alts) === JSON.stringify(['es_MX', 'fr_FR']), 'and the two other languages', JSON.stringify(alts));
  const img = meta('property', 'og:image');
  ok(!!img && img.startsWith(URL_LIVE), 'og:image is an absolute address on this site', img);
  const file = img && path.join(root, img.slice(URL_LIVE.length));
  ok(!!file && fs.existsSync(file), 'and the image is in the repo', file);
  if (file && fs.existsSync(file)) {
    const size = pngSize(file);
    ok(JSON.stringify(size) === '[1200,630]', 'and is 1200 x 630, the size every preview crops to', JSON.stringify(size));
    ok(meta('property', 'og:image:width') === '1200' && meta('property', 'og:image:height') === '630', 'and says so');
    ok(fs.statSync(file).size < 300 * 1024, 'and is under 300 KB', fs.statSync(file).size);
  }
  ok(!!meta('property', 'og:image:alt'), 'og:image:alt');
  ok(meta('name', 'twitter:card') === 'summary_large_image', 'twitter:card summary_large_image');
});

group('Structured data', () => {
  const blocks = [...head.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map(m => m[1]);
  ok(blocks.length === 1, 'one JSON-LD block', blocks.length);
  let data = null;
  try { data = JSON.parse(blocks[0]); } catch (e) { ok(false, 'it parses', e.message); }
  if (!data) return;
  ok(data['@context'] === 'https://schema.org', 'schema.org');
  const items = data['@graph'] || [];
  const web = items.find(i => i['@type'] === 'WebApplication');
  const ios = items.find(i => i['@type'] === 'MobileApplication');
  ok(!!web, 'a WebApplication');
  ok(!!ios, 'and the iOS app as a MobileApplication');
  if (web) {
    ok(web.name === 'Honk It Up!' && web.url === URL_LIVE, 'the web app is named and at the live address', `${web.name} ${web.url}`);
    ok(web.offers && web.offers.price === '0' && web.offers.priceCurrency === 'USD', 'free', JSON.stringify(web.offers));
    ok(web.isAccessibleForFree === true, 'isAccessibleForFree');
    ok(JSON.stringify(web.inLanguage) === JSON.stringify(['en', 'es', 'fr']), 'English, Spanish and French', JSON.stringify(web.inLanguage));
    ok(Array.isArray(web.featureList) && web.featureList.length >= 8, 'a feature list', web.featureList && web.featureList.length);
    ok(web.image && web.image === meta('property', 'og:image'), 'the same picture as the preview');
    ok(web.applicationCategory === 'EducationalApplication', 'an educational app', web.applicationCategory);
    const publisher = web.publisher;
    ok(publisher && publisher.name === 'Massfeller LLC', 'published by the App Store seller', JSON.stringify(publisher));
  }
  if (ios) {
    ok(ios.url === APP_STORE, 'the App Store address', ios.url);
    ok(ios.operatingSystem === 'iOS', 'iOS');
    ok(ios.offers && ios.offers.price === '0', 'free on the App Store too (iTunes lookup, 2026-11-03)', JSON.stringify(ios.offers));
  }
});

group('Sitemap', () => {
  const file = path.join(root, 'sitemap.xml');
  ok(fs.existsSync(file), 'sitemap.xml is in the repo');
  if (!fs.existsSync(file)) return;
  const xml = fs.readFileSync(file, 'utf8');
  ok(xml.startsWith('<?xml') && xml.includes('http://www.sitemaps.org/schemas/sitemap/0.9'), 'a sitemap');
  const locs = [...xml.matchAll(/<loc>([^<]*)<\/loc>/g)].map(m => m[1]);
  ok(JSON.stringify(locs) === JSON.stringify([URL_LIVE]), 'listing the one page', JSON.stringify(locs));
  ok(/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/.test(xml), 'with a date');
});

group('Still loads nothing (the hard constraint)', () => {
  ok(!/<script\b[^>]*\bsrc=/i.test(html), 'no script src');
  ok(!/<link\b[^>]*rel="stylesheet"/i.test(html), 'no stylesheet link');
  ok(!/<link\b[^>]*rel="(preconnect|dns-prefetch|preload)"/i.test(head), 'no preconnect or preload');
  ok(!/<img\b[^>]*src="https?:/i.test(html), 'no remote image');
  // The page's own links in the head are same-site files.
  for (const m of head.matchAll(/<link\b[^>]*href="([^"]*)"/g)) {
    ok(!/^https?:/.test(m[1]) || m[1] === URL_LIVE, `head link ${m[1]} is this site`);
  }
});

group('Public text follows the rules', () => {
  const sitemap = path.join(root, 'sitemap.xml');
  const added = head + (fs.existsSync(sitemap) ? fs.readFileSync(sitemap, 'utf8') : '');
  const text = added.replace(/<!--[\s\S]*?-->/g, '');
  ok(!DASHES.test(text), 'no en or em dash in the tags');
  ok(!/\b(reject|rejection|spam|appeal|4\.3)\b/i.test(text), 'nothing about App Review');
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
