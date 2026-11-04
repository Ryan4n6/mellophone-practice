// scripts/lib/chrome.js
//
// A real headless Chrome driven over the DevTools protocol, for the checks
// that cannot run the page in node (#78, #81): a service worker, a page's
// laid out width. Node's own WebSocket and fetch, nothing installed. Fails
// loudly when there is no Chrome rather than letting a check pass.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const CHROME = process.env.CHROME ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function launchChrome() {
  if (!fs.existsSync(CHROME)) {
    console.log(`FAIL no Chrome at ${CHROME} (set CHROME=...)`);
    process.exit(1);
  }
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'honk-chrome-'));
  const proc = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0',
    `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
    'about:blank'], { stdio: 'ignore' });
  const portFile = path.join(profile, 'DevToolsActivePort');
  for (let i = 0; i < 300 && !fs.existsSync(portFile); i++) await sleep(100);
  if (!fs.existsSync(portFile)) {
    proc.kill();
    console.log('FAIL Chrome did not open its DevTools port in 30 s');
    process.exit(1);
  }
  const devPort = fs.readFileSync(portFile, 'utf8').split('\n')[0];
  const list = await (await fetch(`http://127.0.0.1:${devPort}/json/list`)).json();
  const page = list.find(t => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

  let id = 0;
  const pending = new Map(), waiters = [];
  ws.onmessage = ev => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
    } else if (msg.method) {
      for (const w of waiters.slice()) if (w.method === msg.method) {
        waiters.splice(waiters.indexOf(w), 1); w.resolve(msg.params);
      }
    }
  };
  // Every call gets a deadline. A reply that never comes (seen twice on
  // 2026-11-03, a navigation of a page whose worker was mid-refresh) used to
  // hang the whole check with no output; now it fails and names the call.
  const send = (method, params = {}, ms = 30000) => new Promise((resolve, reject) => {
    const callId = ++id;
    const timer = setTimeout(() => {
      if (pending.delete(callId)) reject(new Error(`no reply to ${method} in ${ms} ms`));
    }, ms);
    pending.set(callId, {
      resolve: v => { clearTimeout(timer); resolve(v); },
      reject: e => { clearTimeout(timer); reject(e); },
    });
    ws.send(JSON.stringify({ id: callId, method, params }));
  });
  const once = (method, ms = 10000) => new Promise((resolve, reject) => {
    const w = { method, resolve };
    waiters.push(w);
    setTimeout(() => { const i = waiters.indexOf(w); if (i >= 0) { waiters.splice(i, 1); reject(new Error(`no ${method} in ${ms} ms`)); } }, ms);
  });
  const evaluate = async (expression, ms = 8000) => {
    const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true, timeout: ms });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result.value;
  };
  await send('Page.enable');
  await send('Runtime.enable');
  return { proc, profile, send, once, evaluate, close: () => new Promise(r => { ws.close(); proc.once('exit', r); proc.kill(); }) };
}

module.exports = { launchChrome, sleep };
