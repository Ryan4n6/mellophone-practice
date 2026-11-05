#!/usr/bin/env node
// Does honkitup.themassfellers.com serve the site, and count it without
// keeping anything that tells one person from another (#1, #86)? And does
// mellophone.themassfellers.com, its first name, still serve it unredirected?
//
//     node scripts/check-edge.js           the Worker's code, against the real GitHub Pages
//     node scripts/check-edge.js --live    the deployed address, from this machine
//
// The first runs edge/worker.js's own fetch handler in node, passing it
// requests the way Cloudflare would and letting it fetch the real github.io
// copy, so it needs a signal but no Cloudflare. The one stand-in is the
// Analytics Engine binding, a recorder with the same writeDataPoint call, so
// what would be counted can be read back. --live then asks the deployed
// address the same questions over the internet. Run it after touching
// edge/, and --live after a deploy.

'use strict';

const path = require('path');
const { pathToFileURL } = require('url');

const LIVE = 'https://honkitup.themassfellers.com';
// The address's first name (#1). Some phones installed the site from it in
// its first two days, so it keeps serving, unredirected, like github.io.
const FIRST = 'https://mellophone.themassfellers.com';
const OLD = 'https://ryan4n6.github.io/mellophone-practice';

let failures = 0, checks = 0;
function ok(cond, what, detail) {
  checks++;
  if (!cond) { failures++; console.log(`  FAIL ${what}${detail !== undefined ? `: ${detail}` : ''}`); }
}
function group(name) { console.log(name); }

// A browser's request as it reaches the Worker. cf is what Cloudflare adds.
const BROWSER = {
  'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1',
  'accept-language': 'es-MX,es;q=0.9,en;q=0.8',
  'accept': 'text/html',
};
function request(url, { method = 'GET', headers = {}, country = 'MX' } = {}) {
  const r = new Request(url, { method, headers: { ...BROWSER, ...headers } });
  Object.defineProperty(r, 'cf', { value: { country } });
  return r;
}

async function bytes(response) { return Buffer.from(await response.arrayBuffer()); }

async function local() {
  const worker = await import(pathToFileURL(path.join(__dirname, '..', 'edge', 'worker.js')).href);
  const { kindOf, isBot, languageOf, hostOf, ORIGIN } = worker;
  const points = [];
  const env = { HITS: { writeDataPoint: p => points.push(p) } };
  const call = (url, opts) => worker.default.fetch(request(url, opts), env);

  group('What a request is');
  const nav = { 'sec-fetch-mode': 'navigate' }, cors = { 'sec-fetch-mode': 'cors' };
  ok(kindOf(request(LIVE + '/', { headers: nav }), '/') === 'open', 'a navigation to the page is an open');
  ok(kindOf(request(LIVE + '/index.html', { headers: nav }), '/index.html') === 'open', 'and by name');
  ok(kindOf(request(LIVE + '/index.html', { headers: cors }), '/index.html') === 'refresh',
    "the offline worker's background fetch of the page is a refresh");
  // Measured in the first hour live: scanners and previews fetch "/" with no
  // Sec-Fetch-Mode at all, and were being counted as refreshes, which read as
  // people. The worker's real refresh is always index.html, in cors mode.
  ok(kindOf(request(LIVE + '/'), '/') === 'page-other', 'a fetch of the page that is neither (a preview, a scanner) is page-other');
  ok(kindOf(request(LIVE + '/', { headers: cors }), '/') === 'page-other', 'and so is a cors fetch of /, which the worker never makes');
  ok(kindOf(request(LIVE + '/icon-192.png', { headers: { 'sec-fetch-mode': 'no-cors' } }), '/icon-192.png') === 'file', 'an icon is a file');
  ok(kindOf(request(LIVE + '/privacy.html', { headers: nav }), '/privacy.html') === 'navigate-other', 'the privacy page is its own kind');
  ok(isBot('Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'), 'Googlebot is a crawler');
  ok(isBot('Mozilla/5.0 (compatible; bingbot/2.0)'), 'bingbot is a crawler');
  ok(!isBot(BROWSER['user-agent']), 'Safari on an iPhone is a person');
  ok(languageOf('es-MX,es;q=0.9') === 'es' && languageOf('fr-CA') === 'fr' && languageOf('en-US') === 'en', 'es, fr and en are kept');
  ok(languageOf('pt-BR') === 'other' && languageOf('') === 'other' && languageOf(undefined) === 'other', 'anything else is other');
  // Which name was used, so we can see when the first one stops being opened.
  ok(typeof hostOf === 'function' && hostOf('honkitup.themassfellers.com') === 'honkitup' &&
    hostOf('mellophone.themassfellers.com') === 'mellophone', 'the two names are told apart');
  ok(typeof hostOf === 'function' && hostOf('honk-it-up.example.workers.dev') === 'other', 'any other host is other');

  group('The page, through the Worker, is the github.io page');
  const direct = await fetch(ORIGIN + '/');
  const directBody = await bytes(direct);
  let r = await call(LIVE + '/', { headers: nav });
  const body = await bytes(r);
  ok(r.status === 200, '/ is 200', r.status);
  ok(body.equals(directBody), 'byte for byte what github.io serves', `${body.length} vs ${directBody.length}`);
  ok(/text\/html/.test(r.headers.get('content-type') || ''), 'as html', r.headers.get('content-type'));
  // no-transform is what stops Cloudflare editing the page on its way out:
  // on 2026-11-03 the first deploy came back 1114 bytes longer, Bot Fight
  // Mode's JavaScript detection injected before </body>, a script that loads
  // /cdn-cgi/challenge-platform. That is the page loading something, and Bot
  // Fight Mode cannot be turned off for one host on a Free zone.
  ok(r.headers.get('cache-control') === `${direct.headers.get('cache-control')}, no-transform`,
    "GitHub's cache header, plus no-transform", r.headers.get('cache-control'));
  for (const f of ['index.html', 'sw.js', 'manifest.webmanifest', 'icon-192.png', 'og-image.png', 'sitemap.xml', 'privacy.html']) {
    r = await call(`${LIVE}/${f}`);
    ok(r.status === 200, `/${f} is 200`, r.status);
    await r.arrayBuffer();
  }
  r = await call(LIVE + '/sw.js');
  ok(/javascript/.test(r.headers.get('content-type') || ''), 'sw.js as javascript, or the browser will not register it', r.headers.get('content-type'));
  await r.arrayBuffer();
  r = await call(LIVE + '/no-such-page-9f3');
  ok(r.status === 404, 'a missing page is 404', r.status);
  await r.arrayBuffer();

  group("GitHub's redirects point at this address");
  r = await call(LIVE + '/scripts');
  ok(r.status === 301, '/scripts is 301 (GitHub adds the slash)', r.status);
  ok(r.headers.get('location') === LIVE + '/scripts/', 'to this address, not github.io', r.headers.get('location'));
  ok(!/github\.io/.test(r.headers.get('location') || ''), 'no Location ever names github.io');

  group('Only reading, and only https');
  r = await call(LIVE.replace('https:', 'http:') + '/?x=1');
  ok(r.status === 301 && r.headers.get('location') === LIVE + '/?x=1', 'http goes to https, keeping the query', `${r.status} ${r.headers.get('location')}`);
  r = await call(LIVE + '/', { method: 'POST' });
  ok(r.status === 405, 'a POST is 405', r.status);
  r = await call(LIVE + '/', { method: 'HEAD' });
  ok(r.status === 200, 'a HEAD is answered', r.status);

  group('What is counted');
  points.length = 0;
  await (await call(LIVE + '/', { headers: nav, country: 'MX' })).arrayBuffer();
  ok(points.length === 1, 'one data point per request', points.length);
  const p = points[0] || { blobs: [], doubles: [], indexes: [] };
  ok(JSON.stringify(p.blobs) === JSON.stringify(['open', '/', 'MX', 'es', 'person', 'honkitup']),
    'kind, path, country, language, crawler or not, which name', JSON.stringify(p.blobs));
  ok(JSON.stringify(p.doubles) === '[200]' && JSON.stringify(p.indexes) === '["open"]', 'and the status', JSON.stringify(p));
  const kept = JSON.stringify(p);
  ok(!kept.includes('Mozilla') && !kept.includes('iPhone'), 'no user agent string is kept');
  ok(!/\d+\.\d+\.\d+\.\d+|[0-9a-f]{1,4}:[0-9a-f:]+:[0-9a-f]{1,4}/i.test(kept), 'no address of any kind is kept');
  ok(!kept.includes('es-MX'), 'the language is narrowed, not the full tag');
  points.length = 0;
  await (await call(LIVE + '/scripts')).arrayBuffer();
  await (await call(LIVE.replace('https:', 'http:') + '/')).arrayBuffer();
  ok(points.length === 1, 'a redirect GitHub sent is counted, the https bounce is not', points.length);
  points.length = 0;
  r = await call(FIRST + '/', { headers: nav });
  const firstBody = await bytes(r);
  ok(r.status === 200 && firstBody.equals(directBody), 'the first name serves the same page, not a redirect', r.status);
  ok(points[0] && points[0].blobs[5] === 'mellophone', 'and is counted under its own name', points[0] && JSON.stringify(points[0].blobs));
  r = await call(FIRST + '/scripts');
  ok(r.headers.get('location') === FIRST + '/scripts/', "GitHub's redirects there stay on that name", r.headers.get('location'));
  await r.arrayBuffer();
  points.length = 0;
  const noBinding = await worker.default.fetch(request(LIVE + '/'), {});
  ok(noBinding.status === 200, 'with no binding the page is still served');
  await noBinding.arrayBuffer();
}

async function live() {
  group(`The deployed address, ${LIVE}`);
  const [a, b] = await Promise.all([fetch(LIVE + '/'), fetch(OLD + '/')]);
  const [ab, bb] = await Promise.all([bytes(a), bytes(b)]);
  ok(a.status === 200, `${LIVE}/ is 200`, a.status);
  ok(ab.equals(bb), 'the same bytes as github.io (Cloudflare added nothing)', `${ab.length} vs ${bb.length}`);
  ok(!ab.includes('/cdn-cgi/') && !ab.includes('__CF$cv$params'), 'no Cloudflare script in the page');
  ok(/no-transform/.test(a.headers.get('cache-control') || ''), 'served no-transform', a.headers.get('cache-control'));
  ok(b.status === 200 && !b.redirected, 'and the old address still serves, not redirected', `${b.status} ${b.url}`);
  const first = await fetch(FIRST + '/', { redirect: 'manual' });
  const fb = await bytes(first);
  ok(first.status === 200 && fb.equals(bb), `${FIRST} still serves the same bytes, not a redirect`, first.status);
  const http = await fetch(LIVE.replace('https:', 'http:') + '/', { redirect: 'manual' });
  ok([301, 308].includes(http.status) && (http.headers.get('location') || '').startsWith(LIVE), 'http goes to https',
    `${http.status} ${http.headers.get('location')}`);
  const dir = await fetch(LIVE + '/scripts', { redirect: 'manual' });
  ok(dir.headers.get('location') === LIVE + '/scripts/', 'a GitHub redirect points here', dir.headers.get('location'));
  for (const f of ['sw.js', 'robots.txt', 'sitemap.xml', '69b727d14809608d988288d897af67eb.txt']) {
    const r = await fetch(`${LIVE}/${f}`);
    ok(r.status === 200, `/${f} is served at the root of the host`, r.status);
    await r.arrayBuffer();
  }
}

(async () => {
  console.log('Edge (#1): the new address serves the site and counts nothing personal');
  try {
    if (process.argv.includes('--live')) await live();
    else await local();
  } catch (e) {
    ok(false, 'the check ran to the end (it needs a signal)', e.stack);
  }
  console.log(`\n${checks - failures}/${checks} checks passed`);
  process.exit(failures ? 1 : 0);
})();
