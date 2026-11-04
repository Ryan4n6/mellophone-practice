// Honk It Up! offline worker (#78).
//
// The page has every asset inline so it works with no signal, but without
// this the page itself still had to come over the network each time it was
// opened: measured on 2026-11-03, the live site gave ERR_INTERNET_DISCONNECTED
// offline. This file holds no app code. If it never registers (an old
// browser, the page opened from a file) the page works exactly as before.
//
// Strategy: serve from the cache at once, then fetch a fresh copy in the
// background and keep it for next time ("stale while revalidate"). A band
// room's signal is often there and useless, so the page must never wait on
// the network when it has a copy; the price is that a push to main shows on
// the SECOND open after it, not the first. scripts/check-offline.js pins both.
//
// Bump CACHE only when this list changes; index.html updates itself.

// v2 dropped './' from the list: every navigation is kept under index.html
// (cacheKey), so a copy under './' was 560 KB that nothing read or refreshed.
const CACHE = 'honk-site-v2';
const SITE = ['index.html', 'manifest.webmanifest',
  'icon-180.png', 'icon-192.png', 'icon-512.png'];

// Every navigation inside the scope is the one page, so it is kept under one
// key: "/", "/index.html" and "/?anything" must not become three copies that
// go stale at different times.
function cacheKey(request) {
  const url = new URL(request.url);
  const scope = new URL(self.registration.scope);
  const page = new URL('index.html', scope).href;
  if (request.mode === 'navigate' || url.href.split('?')[0] === scope.href) return page;
  url.search = '';
  return url.href;
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // cache: 'reload' skips the browser's HTTP cache, so a fresh install
    // never stores a ten minute old copy from it.
    await cache.addAll(SITE.map(u => new Request(u, { cache: 'reload' })));
    console.info(`[OFFLINE] installed ${CACHE}: ${SITE.length} files kept`);
    await self.skipWaiting();
  })().catch(e => {
    console.error(`[OFFLINE] install failed, the page will need a signal: ${e}`);
    throw e;
  }));
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name !== CACHE) {
        await caches.delete(name);
        console.info(`[OFFLINE] dropped old cache ${name}`);
      }
    }
    // Take the page that registered us now, not on its next open.
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  // Only this site's own files. The page fetches nothing else, and a request
  // it did not expect is left to the browser rather than cached.
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  const key = cacheKey(request);
  if (key.endsWith('/sw.js')) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(key);
    // 'no-cache' revalidates with the server instead of taking the HTTP
    // cache's copy, which GitHub Pages lets live for ten minutes.
    const fresh = fetch(key, { cache: 'no-cache' }).then(async response => {
      // A followed redirect still reads ok, and Chrome refuses a redirected
      // response for a navigation. Kept, it would replace the good copy and
      // the next open would be net::ERR_FAILED, online or off, for good: the
      // worker's own update check is redirected too and can never fix it.
      // Measured on 2026-11-03 against what a Pages custom domain does to
      // every old address (#1). So a moved address keeps the copy we have.
      if (response.redirected) {
        console.warn(`[OFFLINE] kept the old copy of ${key}: the address now redirects to ${response.url}`);
      } else if (response.ok) {
        await cache.put(key, response.clone());
        console.info(`[OFFLINE] refreshed ${key}`);
      } else {
        console.warn(`[OFFLINE] kept the old copy of ${key}: server said ${response.status}`);
      }
      return response;
    });
    if (cached) {
      event.waitUntil(fresh.catch(e => console.info(`[OFFLINE] no signal, served ${key} from the cache (${e.message})`)));
      return cached;
    }
    // Nothing kept and the address moved: send the browser there, rather
    // than hand a navigation the redirected response it would refuse.
    return fresh.then(response => response.redirected ? Response.redirect(response.url, 302) : response, e => {
      console.error(`[OFFLINE] ${key} is not cached and there is no signal: ${e.message}`);
      return Response.error();
    });
  })());
});
