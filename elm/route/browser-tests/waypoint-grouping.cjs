// Build with `make route.js wasm`, then run with Playwright and Chromium installed:
// NODE_PATH=/path/to/node_modules node --test elm/route/browser-tests/waypoint-grouping.cjs
// ROUTE_BUNDLE can select a compiled bundle outside data/.
// Uses synthetic state with the real layout, Elm, WASM and IndexedDB adapters.
// No external services or personal routes are used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { test } = require('node:test');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../../..');
const layout = fs.readFileSync(path.join(root, '_layouts/route.html'), 'utf8');
const scripts = layout.slice(layout.indexOf('<script src='), layout.lastIndexOf('</script>') + 9);
const fixture = {
  activeTab: 'cuesheet', distanceDetail: 2, totalDistanceDisplay: 'from zero',
  relativeStart: '0', relativeEnd: '1', routeName: 'Grouping smoke test',
  tracks: {
    previous: [], next: [], current: {
      trackpoints: [[0, 100, 40, -105, 0, 0], [1000, 120, 40.01, -105, 20, 0]],
      gain: 20, loss: 0,
      editableWaypoints: [
        { original: { dist: 300, name: 'Water', categories: ['water'], gain: 6, loss: 0, offRoute: 0 }, deleted: false },
        { original: { dist: 304, name: 'Camp', categories: ['camp'], gain: 6.08, loss: 0, offRoute: 0 }, deleted: false },
      ],
    },
  },
};

async function setDetail(page, detail) {
  await page.getByRole('button', { name: 'Cuesheet', exact: true }).click();
  await page.locator('legend').filter({ hasText: /^Distance detail$/ }).locator('..')
    .locator('input[type=range]').evaluate((input, value) => {
      input.value = String(value);
      input.dispatchEvent(new Event('input', { bubbles: true }));
    }, detail);
  await page.waitForFunction(async detail => JSON.parse(await readStoredState()).distanceDetail === detail, detail);
}

async function groupCount(page, count) {
  await page.waitForFunction(count => document.querySelectorAll('.cuesheet-group').length === count, count);
}

test('detail controls groups, member identity and edits survive regrouping and restore', { timeout: 60000 }, async t => {
  const server = http.createServer((req, res) => {
    const files = {
      '/data/route.js': process.env.ROUTE_BUNDLE || path.join(root, 'data/route.js'),
      '/data/gpx.wasm': path.join(root, 'data/gpx.wasm'),
      '/data/go-wasm-exec.js': path.join(root, 'data/go-wasm-exec.js'),
    };
    if (files[req.url]) {
      res.writeHead(200, { 'Content-Type': req.url.endsWith('.wasm') ? 'application/wasm' : 'text/javascript' });
      res.end(fs.readFileSync(files[req.url]));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`<!doctype html><html><head><meta charset="utf-8"><style>
      body { font: 16px sans-serif; } .row { display: flex; } .column { display: flex; flex-direction: column; }
      .wide { flex: 1; } .page { gap: 24px; } button, select { margin: 3px; }
    </style></head><body><script>
      if (!sessionStorage.getItem('seeded')) {
        localStorage.setItem('appState', JSON.stringify(${JSON.stringify(fixture)}));
        sessionStorage.setItem('seeded', 'true');
      }
    </script>${scripts}</body></html>`);
  });
  let browser;
  t.after(async () => {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1100, height: 800 } });
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  page.on('dialog', async dialog => { errors.push(dialog.message()); await dialog.dismiss(); });
  await page.goto(`http://127.0.0.1:${server.address().port}/`);

  await groupCount(page, 1);
  assert.match(await page.locator('.cuesheet-group').textContent(), /0\.30km/);
  assert.match(await page.locator('.cuesheet-group').getAttribute('aria-label'), /2 waypoints/);
  assert.deepEqual(await page.locator('.cuesheet-member').evaluateAll(nodes => nodes.map(node => node.dataset.waypointIndex)), ['0', '1']);
  await page.getByRole('button', { name: 'Relative', exact: true }).click();
  const end = page.locator('.waypoint-selector').nth(1);
  await end.locator('optgroup').waitFor({ state: 'attached' });
  assert.equal(await end.locator('optgroup').count(), 1);
  assert.deepEqual(await end.locator('optgroup option').evaluateAll(nodes => nodes.map(node => node.value)), ['0', '1']);
  await end.selectOption('0');
  await end.selectOption('1');

  await setDetail(page, 3);
  await groupCount(page, 0);
  assert.equal(await page.locator('.cuesheet-member').count(), 0);
  assert.match(await page.locator('.cuesheet').textContent(), /0\.300km/);
  assert.match(await page.locator('.cuesheet').textContent(), /0\.304km/);
  await page.getByRole('button', { name: 'Relative', exact: true }).click();
  assert.equal(await end.inputValue(), '1');
  assert.equal(await end.locator('optgroup').count(), 0);
  assert.match(await end.locator('option[value="1"]').textContent(), /0\.304km/);

  await setDetail(page, 2);
  await groupCount(page, 1);
  await page.getByRole('button', { name: 'Waypoints', exact: true }).click();
  await page.locator('[data-waypoint-index="0"] input[placeholder="Waypoint name..."]').fill('Water edited');
  await page.locator('[data-waypoint-index="1"] input[placeholder="Waypoint name..."]').fill('Camp edited');
  await page.getByRole('button', { name: 'Cuesheet', exact: true }).click();
  await groupCount(page, 1);
  assert.match(await page.locator('.cuesheet-group').textContent(), /Water edited · Camp edited/);
  const stateDownload = page.waitForEvent('download');
  await page.getByRole('button', { name: 'export state', exact: true }).click();
  const saved = JSON.parse(fs.readFileSync(await (await stateDownload).path(), 'utf8'));
  assert.equal(saved.distanceDetail, 2);
  assert.equal(saved.relativeEnd, '1');
  assert.deepEqual(saved.tracks.current.editableWaypoints.map(w => w.original.dist), [300, 304]);
  assert.deepEqual(saved.tracks.current.editableWaypoints.map(w => w.name), ['Water edited', 'Camp edited']);
  assert.equal(JSON.stringify(saved).includes('members'), false, 'derived groups must not be serialized');

  await page.reload();
  await groupCount(page, 1);
  assert.match(await page.locator('.cuesheet-group').textContent(), /Water edited · Camp edited/);
  if (process.env.GROUPING_SCREENSHOT) await page.screenshot({ path: process.env.GROUPING_SCREENSHOT, fullPage: true });
  await page.getByRole('button', { name: 'Relative', exact: true }).click();
  assert.equal(await end.inputValue(), '1');
  assert.equal(await end.locator('optgroup').count(), 1);

  await page.getByRole('button', { name: 'Elevation Profile', exact: true }).click();
  const gpxDownload = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download splits', exact: true }).click();
  const gpx = fs.readFileSync(await (await gpxDownload).path(), 'utf8');
  // The existing split-GPX contract exports tracks only. Grouping must not
  // change those points; the saved-state assertions above cover both waypoints.
  assert.deepEqual(await page.evaluate(xml => {
    const doc = new DOMParser().parseFromString(xml, 'application/xml');
    return {
      parseError: Boolean(doc.querySelector('parsererror')),
      waypointCount: doc.querySelectorAll('wpt').length,
      points: Array.from(doc.querySelectorAll('trkpt'), node => [
        Number(node.getAttribute('lat')), Number(node.getAttribute('lon')),
        Number(node.querySelector('ele').textContent),
      ]),
    };
  }, gpx), { parseError: false, waypointCount: 0, points: [[40, -105, 100], [40.01, -105, 120]] });
  assert.deepEqual(errors, []);
});
