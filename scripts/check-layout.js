#!/usr/bin/env node
// Does every screen of the website fit a phone (#81)?
//
// Run: node scripts/check-layout.js
//
// One element wider than the phone does not just stick out: a mobile
// browser lays the whole page out that wide and zooms it all down to fit,
// so every word on every screen gets smaller. On 2026-11-03 the Spanish
// "Note names" picker made the page 409 wide on a 320 phone. A select is as
// wide as its longest option, and that is the kind of thing a translation
// changes without anyone touching the layout.
//
// Opens each tab and the tuner in a real headless Chrome as a phone, at 320
// (the narrowest iPhone the App Store still lists) and 375, in English,
// Spanish and French, on a treble horn and a bass one (the chip's name and
// the staff change with the horn), and fails on any screen wider than the
// phone, naming the outermost element that is. About twenty seconds.

'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const { launchChrome, sleep } = require('./lib/chrome');

const ROOT = path.resolve(__dirname, '..');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
  '.webmanifest': 'application/manifest+json', '.png': 'image/png' };

let failures = 0, passes = 0;
function check(ok, what, detail) {
  if (ok) passes++;
  else { failures++; console.log(`  FAIL ${what}${detail ? `: ${detail}` : ''}`); }
}

// Every element sticking out past the phone, outermost only.
const MEASURE = `(() => {
  const width = window.__phoneWidth;
  const all = [...document.body.querySelectorAll('*')].filter(e => e.offsetParent && e.getBoundingClientRect().right > width + 1);
  const outer = all.filter(e => !all.includes(e.parentElement));
  return {
    page: Math.max(document.documentElement.scrollWidth, innerWidth),
    offenders: outer.slice(0, 4).map(e => e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') +
      (typeof e.className === 'string' && e.className ? '.' + e.className.split(' ')[0] : '') + ' to ' + Math.round(e.getBoundingClientRect().right)),
  };
})()`;

(async () => {
  console.log('Layout (#81): every screen fits the phone, in every language');
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p.endsWith('/')) p += 'index.html';
    const file = path.join(ROOT, path.normalize(p));
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(fs.readFileSync(file));
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}/index.html`;
  const chrome = await launchChrome();
  const open = async url => {
    const loaded = chrome.once('Page.loadEventFired', 15000).catch(() => null);
    await chrome.send('Page.navigate', { url });
    await loaded;
    await sleep(250);
  };
  try {
    for (const width of [320, 375]) {
      await chrome.send('Emulation.setDeviceMetricsOverride', { width, height: 700, deviceScaleFactor: 2, mobile: true });
      for (const lang of ['en', 'es', 'fr']) {
        for (const horn of ['mellophone', 'tuba']) {
          await open(base);
          await chrome.evaluate(`localStorage.setItem('mello-language', '${lang}');
            localStorage.setItem('mello-instrument', '${horn}'); true`);
          await open(base);
          await chrome.evaluate(`window.__phoneWidth = ${width}; true`);
          const where = `${width} ${lang} ${horn}`;
          const tabs = await chrome.evaluate(`[...document.querySelectorAll('.tab')].length`);
          check(tabs === 5, `${where}: five tabs`, String(tabs));
          for (let i = 0; i < tabs; i++) {
            const name = await chrome.evaluate(`(() => { const b = document.querySelectorAll('.tab')[${i}]; b.click(); window.scrollTo(0, 0); return b.getAttribute('onclick').match(/'(\\w+)'/)[1]; })()`);
            await sleep(80);
            const m = await chrome.evaluate(MEASURE);
            check(m.page <= width, `${where}: ${name} tab fits`, `page ${m.page} wide; ${m.offenders.join(', ')}`);
          }
          await chrome.evaluate(`document.querySelectorAll('.tab')[0].click(); document.querySelector('.tune-btn').click(); true`);
          await sleep(200);
          const m = await chrome.evaluate(MEASURE);
          check(m.page <= width, `${where}: the tuner fits`, `page ${m.page} wide; ${m.offenders.join(', ')}`);
          await chrome.evaluate(`closeCheck(); true`);
        }
      }
    }
  } catch (e) {
    check(false, 'the check ran to the end', e.message);
  } finally {
    await chrome.close();
    server.close();
    fs.rmSync(chrome.profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  }
  console.log(`\n${passes}/${passes + failures} passed`);
  process.exit(failures ? 1 : 0);
})();
