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

The site includes a service worker (`sw.js`) that provides offline support for the route tools (cue sheet, elevation profile). It caches the WASM module, compiled Elm JS, and other assets for offline use.

## Notes

- The site uses Jekyll with incremental builds enabled
- Markdown is processed with kramdown
- Jekyll plugins: jemoji, jekyll-sitemap
- Site URL: https://www.glyn.io
- CI/CD: GitHub Actions deploys to GitHub Pages on push to `develop`

## Code style
- Avoid single-use variables; inline instead. Function, method and other variable names should support easily understanding what the result of an operation is.

