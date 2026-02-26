const CACHE_VERSION = 'v1';
const PRECACHE_NAME = 'precache-' + CACHE_VERSION;
const RUNTIME_NAME = 'runtime-' + CACHE_VERSION;

// Assets to cache immediately on install, before any user interaction.
const PRECACHE_URLS = [
  '/cycling/route',
  '/css/main.css',
  '/data/route.js',
  '/data/go-wasm-exec.js',
  '/data/gpx.wasm',
  '/data/avva.png',
];

// On install: fetch and cache all precache URLs, then activate immediately
// (skipWaiting bypasses waiting for existing tabs to close).
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(PRECACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting())
  );
});

// On activate: delete caches from previous versions so stale assets don't
// linger, then claim all open tabs so the new SW takes effect immediately.
self.addEventListener('activate', (event) => {
  const currentCaches = [PRECACHE_NAME, RUNTIME_NAME];
  event.waitUntil(
    caches.keys()
      .then((cacheNames) =>
        Promise.all(
          cacheNames
            .filter((name) => !currentCaches.includes(name))
            .map((name) => caches.delete(name))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Google Fonts are cross-origin so we can't precache them. Instead, cache
  // them on first use so they're available offline on subsequent visits.
  // googleapis.com serves the CSS, gstatic.com serves the actual font files.
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(
      caches.open(RUNTIME_NAME).then((cache) =>
        cache.match(event.request).then((cached) => {
          if (cached) return cached;
          return fetch(event.request).then((response) => {
            cache.put(event.request, response.clone());
            return response;
          });
        })
      )
    );
    return;
  }

  // Ignore other cross-origin requests (e.g. analytics) — we don't need
  // to cache or intercept them.
  if (url.origin !== location.origin) return;

  // "navigate" requests are top-level page loads (typing a URL, clicking a
  // link, or reloading). We use network-first here so the user always gets
  // the latest HTML when online, but can still load the page from cache
  // when offline (e.g. mid-ride with no signal).
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          // Update the cache with the fresh response for next offline use.
          const clone = response.clone();
          caches.open(PRECACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Sub-resources (JS, CSS, images, WASM): serve from cache first for speed,
  // falling back to network. These change infrequently so cache-first avoids
  // unnecessary network requests.
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached;
      return fetch(event.request).then((response) => {
        // Cache any newly-fetched assets so they're available offline later.
        const clone = response.clone();
        caches.open(RUNTIME_NAME).then((cache) => cache.put(event.request, clone));
        return response;
      });
    })
  );
});
