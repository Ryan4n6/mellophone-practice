// Honk It Up! at honkitup.themassfellers.com (#1, #86).
//
// It answered first as mellophone.themassfellers.com (2026-11-03), and was
// renamed for the product two days later. Both names are this Worker's and
// both serve: some phones installed the site from the first name, and a
// redirect would leave them on a copy that never refreshes and strand what
// the browser keeps for that address, the same reason github.io serves on.
//
// The site is still built and served by GitHub Pages from main; this Worker
// only passes each request through to it, so a push to main is still the
// whole deploy and this file changes only when its own job does.
//
// Why not a Pages custom domain, which is one CNAME: Pages would then answer
// every github.io address with a 301, and the offline worker (#78) on every
// phone that installed the site turned a 301 into net::ERR_FAILED on every
// open after the first (measured 2026-11-03, now pinned by step 5 of
// scripts/check-offline.js). A redirect would also strand each student's
// practice log, settings and charts, which the browser keeps per address. So
// github.io keeps serving as it always has and this is a second address for
// the same files.
//
// Why a Worker and not a grey-cloud CNAME: the point of the new address is to
// know whether anyone uses the tool, and a DNS-only record means Cloudflare
// never sees a visit. Each request is counted here, at the edge, with nothing
// added to the page (it still loads nothing) and nothing that tells one
// person from another: no IP address, no user agent string, no cookie. What
// is kept is in count() below and on privacy.html.

export const ORIGIN = 'https://ryan4n6.github.io/mellophone-practice';

// Request headers worth passing on: what to send back and in what form, and
// the cache validators that let a revalidation be a 304. Nothing else of the
// visitor's goes to GitHub that the github.io address would not get anyway.
const PASS = ['accept', 'accept-encoding', 'if-none-match', 'if-modified-since', 'range', 'user-agent'];

// What kind of request this is, from what the browser says about it. The
// offline worker's background refresh is a page open too (the copy on screen
// came from the cache), so both are counted, apart. The refresh is always
// index.html in cors mode (sw.js keys every navigation to index.html); a
// fetch of the page that is neither a navigation nor that is a link preview,
// a crawler or a scanner, and in the first hour live those were most of them.
export function kindOf(request, path) {
  const mode = request.headers.get('sec-fetch-mode');
  const page = path === '/' || path === '/index.html';
  if (mode === 'navigate') return page ? 'open' : 'navigate-other';
  if (path === '/index.html' && (mode === 'cors' || mode === 'same-origin')) return 'refresh';
  if (page) return 'page-other';
  return 'file';
}

// Crawlers say so in their user agent. Only the yes or no is kept.
export function isBot(userAgent) {
  return /bot|crawl|spider|slurp|preview|facebookexternalhit|embedly|headless|curl|wget|python|node-fetch|undici/i.test(userAgent || '');
}

// The browser's first language, as the page would read it, narrowed to the
// three the page speaks: anything else is "other", so the count never holds
// a rarer tag that could narrow down who someone is.
export function languageOf(acceptLanguage) {
  const first = (acceptLanguage || '').split(',')[0].trim().slice(0, 2).toLowerCase();
  return ['en', 'es', 'fr'].includes(first) ? first : 'other';
}

// Which of the Worker's names was used, so the count shows when the first
// one stops being opened. Anything else (a workers.dev preview) is "other".
export function hostOf(hostname) {
  if (hostname === 'honkitup.themassfellers.com') return 'honkitup';
  if (hostname === 'mellophone.themassfellers.com') return 'mellophone';
  return 'other';
}

// One data point per request. blobs: kind, path, country, language, bot, host.
// doubles: the status GitHub answered. Analytics Engine keeps it 3 months.
export function count(env, request, url, status) {
  const kind = kindOf(request, url.pathname);
  const point = {
    indexes: [kind],
    blobs: [kind, url.pathname.slice(0, 96), (request.cf && request.cf.country) || 'XX',
      languageOf(request.headers.get('accept-language')), isBot(request.headers.get('user-agent')) ? 'bot' : 'person',
      hostOf(url.hostname)],
    doubles: [status],
  };
  if (!env || !env.HITS) {
    console.warn('[EDGE] no HITS binding, request not counted');
    return point;
  }
  try { env.HITS.writeDataPoint(point); } catch (e) { console.error(`[EDGE] count failed: ${e}`); }
  return point;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.protocol === 'http:') {
      url.protocol = 'https:';
      return Response.redirect(url.href, 301);
    }
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('', { status: 405, headers: { Allow: 'GET, HEAD' } });
    }
    const headers = new Headers();
    for (const name of PASS) if (request.headers.has(name)) headers.set(name, request.headers.get(name));
    let upstream;
    try {
      // manual: a redirect GitHub sends ("/x" to "/x/") must reach the browser
      // pointing at this address, not be followed here or leak github.io.
      upstream = await fetch(ORIGIN + url.pathname + url.search, { method: request.method, headers, redirect: 'manual' });
    } catch (e) {
      console.error(`[EDGE] GitHub Pages unreachable for ${url.pathname}: ${e}`);
      count(env, request, url, 502);
      return new Response('Honk It Up! could not be reached just now. Try again in a minute.', { status: 502 });
    }
    const out = new Response(upstream.body, upstream);
    // Without no-transform Cloudflare edits the page on its way out. Measured
    // on the first deploy, 2026-11-03: Bot Fight Mode's JavaScript detection
    // put a script before </body> that loads /cdn-cgi/challenge-platform, so
    // the page loaded something, which it must never do. Bot Fight Mode
    // cannot be switched off for one host on a Free zone, and switching it
    // off for the zone would change every other site on it; this header is
    // the documented way to keep it out of one response.
    const cache = upstream.headers.get('cache-control');
    if (!/no-transform/.test(cache || '')) out.headers.set('cache-control', cache ? `${cache}, no-transform` : 'no-transform');
    const location = upstream.headers.get('location');
    if (location) {
      const moved = new URL(location, ORIGIN + url.pathname);
      if (moved.href.startsWith(ORIGIN)) out.headers.set('location', url.origin + moved.href.slice(ORIGIN.length));
    }
    count(env, request, url, upstream.status);
    if (upstream.status >= 500) console.error(`[EDGE] GitHub Pages said ${upstream.status} for ${url.pathname}`);
    return out;
  },
};
