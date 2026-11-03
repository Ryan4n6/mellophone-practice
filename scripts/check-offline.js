#!/usr/bin/env node
// Does the website open with no signal, and does a push to main still reach
// it (#78)?
//
// Run: node scripts/check-offline.js
//
// This one cannot run the page's script in node like the other checks: a
// service worker only exists inside a browser. It drives a real headless
// Chrome over the DevTools protocol (Node's own WebSocket, nothing installed)
// against a local server that serves a COPY of the repo, so the check can
// change the page and can switch the server off. Switching the server off is
// the honest version of "no signal": the browser gets nothing back at all,
// which is what a bus gets, and no emulation flag has to be trusted.
//
// What it asserts, in order:
//   1. a first visit puts the page under the worker
//   2. with the server gone, a reload still opens the Trainer
//   3. with the server back and a new page on it, the next open shows the
//      old page (it was served from the cache at once) and the open after
//      that shows the new one (the worker fetched it in the background)
//   4. the manifest and the home screen icon are served, and offline too
//
// About fifteen seconds. Needs Google Chrome; it says so and fails if there
// is none, rather than passing quietly.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');

const ROOT = path.resolve(__dirname, '..');

let failures = 0, passes = 0;
function check(ok, what, detail) {
  if (ok) { passes++; console.log(`  ok   ${what}`); }
  else { failures++; console.log(`  FAIL ${what}${detail ? `: ${detail}` : ''}`); }
}

// ---- the site, served from a scratch copy ---------------------------------

// Only the files the site is made of. The worker's cache list names these
// too; a file it lists that is not here makes install fail, and step 1 says so.
const SITE_FILES = ['index.html', 'sw.js', 'manifest.webmanifest',
  'icon-180.png', 'icon-192.png', 'icon-512.png'];

const site = fs.mkdtempSync(path.join(os.tmpdir(), 'honk-offline-site-'));
for (const f of SITE_FILES) {
  const from = path.join(ROOT, f);
  if (fs.existsSync(from)) fs.copyFileSync(from, path.join(site, f));
}

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
  '.webmanifest': 'application/manifest+json', '.png': 'image/png' };

let server = null;
const served = [];
function startServer(port) {
  return new Promise(resolve => {
    server = http.createServer((req, res) => {
      let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
      if (p.endsWith('/')) p += 'index.html';
      const file = path.join(site, path.normalize(p));
      served.push(p);
      if (!file.startsWith(site) || !fs.existsSync(file)) {
        res.writeHead(404); res.end('not found'); return;
      }
      // What GitHub Pages sends, so the worker is checked against the cache
      // headers it will really meet.
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
        'Cache-Control': 'max-age=600' });
      res.end(fs.readFileSync(file));
    });
    server.listen(port, '127.0.0.1', () => resolve(server.address().port));
  });
}
function stopServer() {
  return new Promise(resolve => {
    server.closeAllConnections();
    server.close(() => resolve());
  });
}

const { launchChrome, sleep } = require('./lib/chrome');

// The page as the student sees it: is the Trainer there, and which copy of
// the page is it?
const PAGE_STATE = `(() => ({
  url: location.href,
  trainer: !!document.getElementById('panel-trainer'),
  title: document.title,
  marker: (document.documentElement.outerHTML.match(/offline-check-marker-(\\d+)/) || [])[1] || null,
  controlled: !!(navigator.serviceWorker && navigator.serviceWorker.controller),
}))()`;

async function open(chrome, url) {
  const loaded = chrome.once('Page.loadEventFired', 10000).catch(() => null);
  const nav = await chrome.send('Page.navigate', { url });
  await loaded;
  await sleep(300);
  return { errorText: nav.errorText || null, ...(await chrome.evaluate(PAGE_STATE)) };
}

async function reload(chrome, url) {
  // A navigation, not Page.reload: a reload of an error page reloads the
  // error page, and a student opening the app again starts from its address.
  return open(chrome, url);
}

// The worker revalidates in the background. Wait until the copy in the
// cache IS the new page, read out of the cache itself, rather than guessing
// a delay or trusting a flag the page sets.
async function waitForRefresh(chrome, ms = 8000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    const got = await chrome.evaluate(`(async () => {
      const r = await caches.match('index.html', { ignoreSearch: true });
      return !!r && (await r.text()).includes('offline-check-marker-2');
    })()`).catch(() => false);
    if (got) return true;
    await sleep(200);
  }
  return false;
}

(async () => {
  console.log('Offline (#78): the website opens with no signal and still updates');
  const port = await startServer(0);
  const base = `http://127.0.0.1:${port}/`;
  const chrome = await launchChrome();
  let exitCode = 1;
  try {
    // 1. First visit, online.
    let s = await open(chrome, base);
    check(s.trainer, 'first visit opens the Trainer', JSON.stringify(s));
    const ready = await chrome.evaluate(`(async () => {
      if (!('serviceWorker' in navigator)) return 'no serviceWorker in navigator';
      const t = new Promise(r => setTimeout(() => r('timeout'), 6000));
      const r = await Promise.race([navigator.serviceWorker.ready.then(() => 'ready'), t]);
      return r;
    })()`, 10000);
    check(ready === 'ready', 'a service worker installs on the first visit', ready);
    // The first visit is not controlled until the worker claims it; the
    // second open is, and that is the one that matters on a bus.
    s = await reload(chrome, base);
    check(s.controlled, 'the next open is served by the worker', JSON.stringify(s));

    // 2. No signal. The browser's own HTTP cache is emptied first: the
    // server says max-age=600, as GitHub Pages does, so for ten minutes after
    // a visit Chrome serves the page from that cache with or without a worker,
    // and the first run of this check passed four steps on main that way. A
    // student opens the app the next day, after that cache has gone stale.
    // Cache Storage, where the worker keeps its copy, is not touched by this.
    await chrome.send('Network.enable');
    await chrome.send('Network.clearBrowserCache');
    await stopServer();
    const before = served.length;
    s = await reload(chrome, base);
    check(s.trainer && !s.errorText, 'with the server gone, the page still opens the Trainer',
      JSON.stringify(s));
    check(served.length === before, 'and nothing reached the (stopped) server');
    const inst = await chrome.evaluate(`(document.querySelector('.inst-chip') || {}).value || null`).catch(e => String(e));
    check(inst === 'mellophone', 'the page script ran offline (the horn picker is filled in)', inst);
    s = await reload(chrome, base + 'index.html');
    check(s.trainer, 'index.html by name opens offline too', JSON.stringify(s));
    const offlineAssets = await chrome.evaluate(`(async () => {
      const out = {};
      for (const f of ['manifest.webmanifest', 'icon-180.png', 'icon-192.png', 'icon-512.png']) {
        try { const r = await fetch(f); out[f] = r.status; } catch (e) { out[f] = 'error'; }
      }
      return out;
    })()`);
    check(Object.values(offlineAssets).every(v => v === 200), 'manifest and icons are served offline',
      JSON.stringify(offlineAssets));

    // 3. A push to main.
    const html = fs.readFileSync(path.join(site, 'index.html'), 'utf8');
    fs.writeFileSync(path.join(site, 'index.html'),
      html.replace('</body>', '<!-- offline-check-marker-2 --></body>'));
    await startServer(port);
    await chrome.send('Network.clearBrowserCache');
    s = await reload(chrome, base);
    check(s.trainer && s.marker === null,
      'the first open after a push shows the cached page at once', JSON.stringify(s));
    const refreshed = await waitForRefresh(chrome);
    check(refreshed, 'the worker fetched the new page in the background');
    s = await reload(chrome, base);
    check(s.marker === '2', 'the open after that shows the new page', JSON.stringify(s));

    // 4. Installable.
    const manifest = await chrome.evaluate(`(async () => {
      const link = document.querySelector('link[rel="manifest"]');
      const touch = document.querySelector('link[rel="apple-touch-icon"]');
      if (!link) return { error: 'no <link rel="manifest">' };
      const m = await (await fetch(link.href)).json();
      return { name: m.name, start: m.start_url, display: m.display,
        icons: (m.icons || []).map(i => i.sizes), touch: touch ? touch.getAttribute('href') : null };
    })()`);
    check(manifest.name === 'Honk It Up!', 'the manifest names the app', JSON.stringify(manifest));
    check(manifest.display === 'standalone', 'it opens like an app from the home screen', manifest.display);
    check(JSON.stringify(manifest.icons) === JSON.stringify(['192x192', '512x512']),
      'it carries the 192 and 512 icons', JSON.stringify(manifest.icons));
    check(manifest.touch === 'icon-180.png', 'an iPhone gets the 180 point home screen icon', manifest.touch);
    exitCode = failures ? 1 : 0;
  } catch (e) {
    check(false, 'the check ran to the end', e.message);
  } finally {
    await chrome.close();
    if (server && server.listening) await stopServer();
    fs.rmSync(site, { recursive: true, force: true });
    fs.rmSync(chrome.profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  }
  console.log(`\n${passes}/${passes + failures} passed`);
  process.exit(failures ? 1 : exitCode);
})();
