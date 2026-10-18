// Build with `make route.js wasm`, then run with Playwright and Chromium installed:
// NODE_PATH=/path/to/node_modules node --test elm/route/browser-tests/gps-persistence.cjs
// ROUTE_BUNDLE can select an older compiled bundle to reproduce the regression.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { test } = require('node:test');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../../..');
const layout = fs.readFileSync(path.join(root, '_layouts/route.html'), 'utf8');
const scripts = layout.slice(layout.indexOf('<script src='), layout.lastIndexOf('</script>') + 9);

async function savedState(page, expected) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const state = await page.evaluate(async () => JSON.parse(await readStoredState()));
    if (expected(state)) return state;
    await page.waitForTimeout(50);
  }
  assert.fail('Expected state was not saved');
}

function positionInput(page) {
  return page.locator('legend').filter({ hasText: /^Position$/ }).locator('..').locator('input');
}

async function setRange(page, legend, value) {
  await page.locator('legend').filter({ hasText: legend }).locator('..')
    .locator('input[type=range]').first().evaluate((input, value) => {
      input.value = String(value);
      input.dispatchEvent(new Event('input', { bubbles: true }));
    }, value);
}

async function exportedState(page) {
  const downloaded = page.waitForEvent('download');
  await page.getByRole('button', { name: 'export state', exact: true }).click();
  return JSON.parse(fs.readFileSync(await (await downloaded).path(), 'utf8'));
}

function withoutPosition(state) {
  assert.equal(Object.hasOwn(state, 'position'), false, 'GPS position must not be saved or exported');
  assert.equal(Object.hasOwn(state, 'location'), false, 'GPS metadata must remain transient');
}

test('GPS stays transient across saves, export and reload; manual positions survive', { timeout: 60000 }, async t => {
  const server = http.createServer((req, res) => {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const files = {
      '/data/route.js': process.env.ROUTE_BUNDLE || path.join(root, 'data/route.js'),
      '/data/gpx.wasm': path.join(root, 'data/gpx.wasm'),
      '/data/go-wasm-exec.js': path.join(root, 'data/go-wasm-exec.js'),
    };
    if (pathname === '/cycling/route') {
      res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
      res.end('<!doctype html><html><head><meta charset="utf-8"></head><body>' + scripts + '</body></html>');
    } else if (files[pathname]) {
      res.writeHead(200, {
        'Content-Type': pathname.endsWith('.wasm') ? 'application/wasm' : 'text/javascript',
        'Cache-Control': 'no-store',
      });
      res.end(fs.readFileSync(files[pathname]));
    } else {
      res.writeHead(404);
      res.end();
    }
  });
  let browser;
  t.after(async () => {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ serviceWorkers: 'block' });
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  page.on('dialog', async dialog => {
    errors.push(dialog.message());
    await dialog.dismiss();
  });
  // Exercise the real layout's geolocation callbacks and Elm ports, deterministically.
  await page.addInitScript(() => {
    navigator.geolocation.getCurrentPosition = (success, failure) => {
      if (window.testLocationError) failure({ code: window.testLocationError });
      else success({ coords: window.testLocation });
    };
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/cycling/route`);
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: /^upload GPX$/i }).first().click();
  await (await chooser).setFiles(path.join(root, 'data/nosoco24-0.gpx'));
  const uploaded = await savedState(page, state => state?.tracks?.current?.trackpoints?.length > 0);
  await positionInput(page).waitFor();
  const point = uploaded.tracks.current.trackpoints[Math.floor(uploaded.tracks.current.trackpoints.length / 2)];
  // Stored points use compact arrays: distance, elevation, latitude, longitude, gain, loss.
  const gps = { latitude: point[2], longitude: point[3], accuracy: 3, altitude: null };
  await page.evaluate(gps => { window.testLocation = gps; }, gps);

  await setRange(page, /^Position$/, 1000);
  assert.equal((await savedState(page, state => state?.position === 1000)).position, 1000);
  await page.getByRole('button', { name: 'Refresh Location', exact: true }).click();
  await page.getByText('Accuracy: 3m', { exact: true }).waitFor();
  withoutPosition(await savedState(page, state => state && !Object.hasOwn(state, 'position')));

  // This ordinary saved-control update reproduced the bug: it used to save the GPS distance.
  await setRange(page, /^Font size/, 24);
  withoutPosition(await savedState(page, state => state?.fontSize === 24));
  await setRange(page, /^Splits$/, 3);
  withoutPosition(await savedState(page, state => state?.splitEquidistantCount === 3));
  await page.getByRole('button', { name: 'Clear position', exact: true }).waitFor();
  withoutPosition(await exportedState(page));
  await page.getByRole('button', { name: 'Waypoints', exact: true }).click();
  withoutPosition(await savedState(page, state => state?.activeTab === 'waypoints'));
  await page.getByRole('button', { name: 'Elevation Profile', exact: true }).click();

  await page.getByRole('button', { name: 'Start Tracking', exact: true }).click();
  await page.getByRole('button', { name: 'Stop Tracking', exact: true }).click();
  await page.evaluate(() => { window.testLocationError = 3; });
  await page.getByRole('button', { name: 'Refresh Location', exact: true }).click();
  await page.getByText('Location request timed out', { exact: true }).waitFor();
  await setRange(page, /^Font size/, 26);
  withoutPosition(await savedState(page, state => state?.fontSize === 26));
  await page.reload();
  await positionInput(page).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Clear position', exact: true }).count(), 0);

  // A failed first fix does not turn a manual position into a transient one.
  await setRange(page, /^Position$/, 1000);
  await page.evaluate(() => { window.testLocationError = 1; });
  await page.getByRole('button', { name: 'Refresh Location', exact: true }).click();
  await page.getByText('Location permission denied', { exact: true }).waitFor();
  await setRange(page, /^Font size/, 28);
  assert.equal((await savedState(page, state => state?.fontSize === 28)).position, 1000);
  const manual = await exportedState(page);
  assert.equal(manual.position, 1000);
  await page.reload();
  await positionInput(page).waitFor();
  assert.equal(await positionInput(page).inputValue(), '1000');

  // Even entering the same distance as the GPS fix explicitly makes it manual.
  await page.evaluate(gps => { window.testLocation = gps; }, {
    ...gps,
    latitude: uploaded.tracks.current.trackpoints[0][2],
    longitude: uploaded.tracks.current.trackpoints[0][3],
  });
  await page.getByRole('button', { name: 'Refresh Location', exact: true }).click();
  await page.getByText('Accuracy: 3m', { exact: true }).waitFor();
  withoutPosition(await savedState(page, state => state && !Object.hasOwn(state, 'position')));
  const distance = Number(await positionInput(page).inputValue());
  assert.equal(distance, 0);
  await setRange(page, /^Position$/, distance);
  assert.equal((await savedState(page, state => state?.position === distance)).position, distance);
  await setRange(page, /^Font size/, 30);
  assert.equal((await savedState(page, state => state?.fontSize === 30)).position, distance);
  await page.getByRole('button', { name: 'Clear position', exact: true }).click();
  withoutPosition(await savedState(page, state => state && !Object.hasOwn(state, 'position')));

  await setRange(page, /^Position$/, 0);
  assert.equal((await savedState(page, state => state?.position === 0)).position, 0);
  const importChooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'import state', exact: true }).click();
  await (await importChooser).setFiles({
    name: 'manual-position.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(manual)),
  });
  assert.equal((await savedState(page, state => state?.position === 1000)).position, 1000);
  assert.deepEqual(errors, []);
});
