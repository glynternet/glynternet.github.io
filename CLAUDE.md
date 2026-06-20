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
make fat-biking      # Generates data/calendars/fat-biking.ics
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

Calendar events are defined in YAML files (`cycling-events.yml`, `fat-biking.yml`) and converted to iCalendar format.

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
- `fat-biking.yml` is DEPRECATED - use `cycling-events.yml` instead
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

The route app is one monolithic Elm file (~4200 lines). To orient quickly:

- **Rough section map** (line numbers approximate — grep the names):
  - Model/`State`, option records, and defaults: ~`type alias State` through `defaultCuesheetOptions`
  - `Msg` + `update`
  - Elevation profile rendering: `viewElevationProfileTab`, `profile`, `distanceMarkers`
  - Cuesheet rendering: `viewCuesheetTab`, `cuesheetSvg`, `waypointInfos`
  - Distance/elevation display logic: `displayedDistanceValue`, `displayIsPercent`
  - Format helpers: `formatKm`, `formatM`, `formatEleGainLoss`, `formatPercent`
  - Serialization: `parseTotalDistanceDisplay` / `formatTotalDistanceDisplay`, plus the encode/decode of `State`
- **`TotalDistanceDisplay` is the central enum for distance/elevation display.** Both the cuesheet and the elevation profile key off the single `state.cuesheet.totalDistanceDisplay`. To find everything affected by a display mode, grep `TotalDistanceDisplay` / `totalDistanceDisplay`; the Elm compiler's exhaustive `case` checking then flags every site to update when you add a constructor.
- **Data model** (`elm/shared/src/GpxApi.elm`): `TrackPoint.gain`/`.loss` are **cumulative** from the start; route totals live in `EditableTrack.gainLoss` / `Track.gainLoss`; `lastTrackpointDistance` gives total distance; `cumulativeGainLossAtDistance` looks up cumulative climb at any distance (used to build the current-position cuesheet row).
- Build/typecheck with `make route.js` (compiles to `data/route.js`).

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
_calendar/cycling-events.yml (source)
    ↓
    ├── (Makefile copies) → _data/cycling_events.yml → Jekyll reads for HTML page
    └── (generate_ics.py) → data/calendars/cycling-events.ics → Available for download
```

## Cycling Calendar Page

A human-readable calendar page is available at `/cycling/calendar` (`_pages/cycling_calendar.md`).

- The page is generated from `_data/cycling_events.yml` using Jekyll's Liquid templating
- Events are grouped by year and sorted chronologically
- The page regenerates automatically when the YAML data changes
- Linked from the main cycling page with a 📅 emoji

## Development Workflow

1. Edit YAML calendar files in `_calendar/`
2. Run `make all` to regenerate `.ics` files and copy YAML to `_data/`
3. Commit YAML sources, generated `.ics` files, and `_data/cycling_events.yml`
4. The parent Makefile's `make image` includes calendar generation via `make calendars`

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

