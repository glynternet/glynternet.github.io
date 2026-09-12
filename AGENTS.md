# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Jekyll-based static website (glynternet.github.io) that includes cycling event calendars, route planning tools, and various personal content. The `_calendar/` directory contains YAML event definitions that are converted to iCalendar (.ics) format and also used to generate human-readable calendar pages. The site is deployed via GitHub Actions (`.github/workflows/pages.yml`) on pushes to the `develop` branch.

## Build Commands

### Building Calendar Files
From the root directory:
```bash
make calendars
```

From the `_calendar/` directory:
```bash
# Build all calendars (generates .ics files in data/calendars/)
make all

# Build specific calendar
make cycling-events  # Generates data/calendars/cycling-events.ics and copies YAML to _data/
```

### Building the Entire Site
From the root directory:
```bash
# Build entire site (includes calendars, WASM, Elm route app, and Jekyll)
make image

# Serve site locally on http://[::1]:4000
make serve

# Build just the calendars
make calendars

# Build the unified route Elm application (cuesheet + elevation profile)
make route.js            # Compiles elm/route to data/route.js

# Build WASM module (GPX profile data server)
make wasm                # Builds wasm/ Go code to data/gpx.wasm

# Get shell access to Docker containers
make sh        # Jekyll container
make elm-sh    # Elm container
```

## Calendar Format

Calendar events are defined in `cycling-events.yml` and converted to iCalendar format.

### YAML Event Structure
```yaml
name: Calendar Name
events:
  - summary: Event Title
    begin: YYYY-MM-DD
    end: YYYY-MM-DD          # Optional
    location: Location details
    description: Event description text  # Optional
    series: Series Name                  # Optional
    urls:                                # Optional
      - https://example.com
      - https://example2.com
```

### Key Points
- Generated `.ics` files are output to `data/calendars/`
- `cycling-events.yml` is also copied to `_data/cycling_events.yml` for Jekyll's data files feature
- `generate_ics.py` converts the YAML to .ics format using the `ics` Python library

## Project Architecture

This is a Jekyll static site with the following structure:
- `_calendar/`: Calendar YAML sources
- `_data/`: Jekyll data files (includes cycling_events.yml copied from _calendar/)
- `data/`: Build outputs (calendars, compiled Elm JS, WASM, GPX files, images)
- `elm/`: Elm applications for interactive features
  - `elm/route/`: Unified route application (cue sheet + elevation profile + splits)
  - `elm/shared/`: Shared Elm modules (GpxApi, Zipper, Location)
- `wasm/`: Go source for GPX WASM module (profile data server)
- `_pages/`: Jekyll page content (Markdown files for site pages)
- `_layouts/`: Jekyll templates
- `_includes/`: Jekyll partials
- `_sass/`: Stylesheets

### Navigating `elm/route/src/Main.elm`

The route app is one monolithic Elm file (~5800 lines). To orient quickly:

- **Rough section map** (line numbers approximate — grep the names):
  - Model/`State`, option records, and defaults: ~`type alias State` through `defaultPaceOptions`
  - `Msg` + `update`
  - Elevation profile rendering: `viewElevationProfileTab`, `profile`, `distanceMarkers`
  - Cuesheet rendering: `viewCuesheetTab`, `cuesheetSvg`, `waypointInfos`
  - Relative rendering: `viewRelativeTab`, `viewRelativeTravelCard`, `relativePointFor`
  - Pace rendering: `viewPaceTab`, `paceMetresPerSecond`, `viewArrivalCard`
  - Distance/elevation display logic: `displayedDistanceValue`, `displayIsPercent`
  - Serialization: `parseTotalDistanceDisplay` / `formatTotalDistanceDisplay`, plus the encode/decode of `State`
- **`TotalDistanceDisplay` is the central enum for distance/elevation display.** Both the cuesheet and the elevation profile key off the single `state.cuesheet.totalDistanceDisplay`. To find everything affected by a display mode, grep `TotalDistanceDisplay` / `totalDistanceDisplay`; the Elm compiler's exhaustive `case` checking then flags every site to update when you add a constructor.
- **`PointRef` is the vocabulary for "a point on the route"** — a waypoint, the current position, or either end of the track. Every flow that asks the user to choose one stores a `PointRef` and shows `viewPointSelector`; `resolvePointRef` turns it into a `GpxApi.Waypoint`, and `selectedWaypointFor` does the same but only ever resolves to a waypoint the dropdown is still offering (so a filtered-out one reads as "nothing chosen"). Adding a constructor makes the compiler point at every flow that has to answer for it.
- **The device clock lives in `state.now` / `state.zone`, and only the Pace tab uses it.** Both are transient — a stored clock reading is a wrong one the moment it is read back — so they are excluded from `encodeSavedState` and lifted across a state import by hand, alongside `profilePixelWidth`. `Time.every` is subscribed only while the Pace tab is active, so no other tab pays for a ticking clock.
- **Data model** (`elm/shared/src/GpxApi.elm`): `TrackPoint.gain`/`.loss` are **cumulative** from the start; route totals live in `EditableTrack.gainLoss` / `Track.gainLoss`; `lastTrackpointDistance` gives total distance; `cumulativeGainLossAtDistance` looks up cumulative climb at any distance (used to build the current-position cuesheet row).
- Build/typecheck with `make route.js` (compiles to `data/route.js`); run the Elm tests with `make elm-test`.

### Elm modules outside `Main.elm`

`elm/shared/src/` holds the parts that know nothing about the app: `GpxApi`, `Location`,
`Zipper`, plus `Wallclock` (times of day, durations, and the wall-clock datetime a
`datetime-local` input deals in), `Format` (figures in the units they are read in) and `Ui`
(the card, section, row, note and notice the Relative and Pace tabs are built from — all
`Html msg`, so they stay ignorant of `Msg`). `elm/route/elm.json`'s source-directories point
there, so a module dropped in is importable with no further wiring.

`Wallclock` is the one with tests (`elm/route/tests/`), because `daysFromCivil` is arithmetic
that could be subtly wrong for years without ever looking wrong. **`Wallclock` differences two
wall-clock times without a timezone database**, so a span crossing a daylight-saving change is
out by that hour — documented on `elapsedSinceRideStart`, and immaterial next to the accuracy
of a pace estimate.

`docs/module-extraction.md` records what has been extracted and the two extractions still
outstanding — the Pace arithmetic and the `PointRef`/track model — with the call-site counts,
the snag each one runs into, and the tests the Pace one should arrive with. Pick either up
from there.

The Elm toolchain is pinned in `elm.Dockerfile` (`elm@0.19.1-6`, `elm-test@0.19.1-revision12`).
Leave it pinned: `npm install -g elm` now resolves to 0.19.2, which refuses to build an
`elm.json` that asks for 0.19.1, so an unpinned rebuild breaks `make route.js` with no change
to the repo. `make elm-docker-image` rebuilds it.

### Where route state is saved

The route app persists one blob — the track, the waypoint edits and every view
option together, so that a future "share this view" feature can hand over the
whole thing — through the `storeState` port, which `_layouts/route.html` writes
to **IndexedDB** (database `route`, store `state`, key `appState`).

It used to be `localStorage`, and a long route broke it: the state is almost
entirely trackpoints, and a few tens of thousands of them exceeded the ~5MB
per-origin cap, so uploading a big GPX died on an uncaught `QuotaExceededError`.
Two things guard against that now, and both are worth keeping:

- `GpxApi.encodeStoredTrackpoints` writes each point as a fixed-order array of
  rounded numbers (~48 characters a point instead of ~118). `decodeTrackpoints`
  reads that **and** the WASM module's named-field form, which is still what
  crosses the port to Go — don't collapse the two encoders into one.
- A write that the browser refuses no longer throws into the void: it falls back
  to `localStorage`, and if that fails too the message reaches Elm on the
  `storeStateFailed` port and shows as a banner, leaving the route usable.

State written by an older build is migrated out of `localStorage` on first load.

### Important: `_data/` vs `data/` Directories

These two directories serve different purposes and are **both necessary**:

**`_data/` (Jekyll data files):**
- Jekyll's built-in data files feature
- Jekyll automatically reads YAML/JSON/CSV files and makes them available as `site.data.*` in Liquid templates
- Example: `_data/cycling_events.yml` becomes accessible as `site.data.cycling_events` in templates
- Files here are **processed by Jekyll** but not directly copied to the output site
- Used by `_pages/cycling_calendar.md` to generate the HTML calendar page

**`data/` (Static assets):**
- Custom directory for static files that are copied to `_site/data/` as-is
- Contains generated files: `.ics` calendars, compiled Elm JS, GPX files, images
- Files are **NOT processed** by Jekyll, just copied directly
- Directly accessible at URLs like `/data/calendars/cycling-events.ics` for downloads

**Why both are needed for calendars:**
```
_calendar/cycling-events.yml (source, the only committed file of the three)
    ↓  `make calendars` — run by CI before `jekyll build`, and locally by `make serve`/`make image`
    ├── (Makefile copies) → _data/cycling_events.yml → Jekyll reads for HTML page
    └── (generate_ics.py) → data/calendars/cycling-events.ics → Available for download
```

Both outputs are gitignored and built in CI (`.github/workflows/pages.yml` installs the pinned deps from `_calendar/requirements.txt`, then runs `make calendars`). `ics` must stay pinned to `0.8.0.dev0` — the stable 0.7.x line uses `Event.name` instead of `Event.summary` and has no `geo` support. Because the generated files are no longer committed, their directories can be absent on a fresh clone, which is why the `_calendar/Makefile` rules `mkdir -p` first.

**Missing calendar data does not fail a build.** The calendar page renders events client-side from `const eventsData = {{ site.data.cycling_events.events | jsonify }}`, so if `_data/cycling_events.yml` is absent Jekyll emits `eventsData = null`, exits 0, and publishes an empty calendar. `_calendar/verify_published_calendar.py <site-dir>` guards against this by checking the built output against the source YAML (event counts in both the `.ics` and the page); CI runs it between the Jekyll build and the artifact upload, so a silently-empty calendar can never deploy.

**Watch out for stale local previews.** `_config.yml` sets `incremental: true`, and Jekyll's incremental mode does not treat `_data/` changes as invalidating the pages that read them — so after editing `cycling-events.yml` a local build can serve an old calendar. Delete `_site` and `.jekyll-metadata` to force a full rebuild. CI is unaffected: it always builds from a clean checkout. Running the verify script locally against `_site` will catch it.

## Cycling Calendar Page

A human-readable calendar page is available at `/cycling/calendar` (`_pages/cycling_calendar.md`).

- The page is generated from `_data/cycling_events.yml` using Jekyll's Liquid templating
- Events are grouped by year and sorted chronologically
- The page regenerates automatically when the YAML data changes
- Linked from the main cycling page with a 📅 emoji

## Development Workflow

1. Edit YAML calendar files in `_calendar/`
2. Commit the YAML source only — **do not commit generated calendar files.** `_data/cycling_events.yml` and `data/calendars/cycling-events.ics` are gitignored and regenerated by CI on every build, so editing the YAML (including via the GitHub web editor) is enough to publish.
3. Run `make all` locally when you want to preview or inspect the generated output; `make serve` and `make image` regenerate it for you via `make calendars`.

Event UIDs in the generated `.ics` are derived from the event summary and start year (`race-in-the-clouds-2027@glyn.io`). This is deliberate: calendar clients key events by UID, so a UID that changed per build would make subscribers delete and recreate every event on each deploy. Keep `generate_ics.py`'s `event_uid` deterministic. The build fails on a UID collision (two events with the same summary in the same year).

## Docker Usage

The project uses Docker for consistent build environments:
- Jekyll site building uses `glynternet/glynternet:latest`
- Elm compilation uses `glynternet/elm:latest`
- All builds are designed to run in containers with volume mounts

## Service Worker

The site includes a service worker (`sw.js`) that provides offline support for the route tools (cue sheet, elevation profile). It precaches the WASM module (`/data/gpx.wasm`), compiled Elm JS (`/data/route.js`), the Go WASM shim, the route page (`/cycling/route`) and `/css/main.css`, and serves sub-resources **cache-first** for speed.

### Cache busting (how new builds reach online users)

Because sub-resources are served **cache-first** and the route page loads `route.js` via a plain `<script src="/data/route.js">` (no content hash in the URL), a returning online user keeps running the **old** assets until the service worker itself changes. The only cache-busting lever is `CACHE_VERSION` in `sw.js`: changing it makes the browser detect a new SW on the next navigation → `install` re-precaches fresh assets → `activate` deletes the old-version caches → `skipWaiting()` + `clients.claim()` apply it immediately (already-open tabs need a reload; new navigations update).

**This is automated.** `sw.js` carries Jekyll frontmatter so it is Liquid-processed, and `CACHE_VERSION` is stamped from `{{ site.time | date: "%Y%m%d%H%M%S" }}` at build time. Every deploy therefore produces a new version and busts caches with no manual step. Tradeoff: each deploy re-precaches all assets even when unchanged (small, infrequent). The deploy (`.github/workflows/pages.yml`) only runs `jekyll build` on committed files, so the compiled `data/route.js` must be committed for changes to ship.

### Bad-connection safety (why a flaky update never breaks a user)

- **Fully offline:** the browser never re-checks `sw.js`, so the device just keeps running the already-installed SW and its cached assets. The user stays on the working old version.
- **Connection drops mid-update:** install fetches all precache URLs inside `Promise.all` within `event.waitUntil` (and `cache: 'reload'` to bypass the HTTP cache). This is **all-or-nothing** — if any asset fails to download, the promise rejects, install fails, the new SW is discarded, and the old SW + old caches stay fully intact (cache deletion only happens in `activate`, which runs only after a complete install; `skipWaiting()` is chained after the precache succeeds). There is no half-updated state; the browser retries on a later navigation. **Preserve this atomicity in any SW change.**

## Notes

- The site uses Jekyll with incremental builds enabled
- Markdown is processed with kramdown
- Jekyll plugins: jemoji, jekyll-sitemap
- Site URL: https://www.glyn.io
- CI/CD: GitHub Actions deploys to GitHub Pages on push to `develop`

## Code style
- Avoid single-use variables; inline instead. Function, method and other variable names should support easily understanding what the result of an operation is.

