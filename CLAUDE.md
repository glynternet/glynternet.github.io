# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Jekyll-based static website (glynternet.github.io) that includes cycling event calendars, route planning tools, and various personal content. The `_calendar/` directory contains YAML event definitions that are converted to iCalendar (.ics) format and also used to generate human-readable calendar pages.

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
# Build entire site (includes calendars, Elm apps, and Jekyll)
make image

# Serve site locally on http://[::1]:4000
make serve

# Build just the calendars
make calendars

# Build Elm applications
make cuesheet.js         # Compiles elm/cuesheet to data/cuesheet.js
make elevationprofile.js # Compiles elm/elevationprofile to data/elevationprofile.js

# Get shell access to Docker containers
make sh        # Jekyll container
make elm-sh    # Elm container
```

## Calendar Format

Calendar events are defined in YAML files (`cycling-events.yml`, `fat-biking.yml`) and converted to iCalendar format using the `yaml2ics` tool.

### YAML Event Structure
```yaml
name: Calendar Name
events:
  - summary: Event Title
    begin: YYYY-MM-DD
    end: YYYY-MM-DD          # Optional
    location: |
      Location details
    description: |
      text: Event description text
      series: Series Name    # Optional
      urls:
        - https://example.com
        - https://example2.com
```

**Description Field Schema:**
The `description` field uses the `|` literal block indicator to contain YAML-formatted content as a string:
- `text:` (optional): Human-readable description of the event
- `series:` (optional): Name of the series that the event is part of
- `urls:` (optional): List of related URLs, each prefixed with `- `

Example:
```yaml
description: |
  text: Multi-day bikepacking event
  series: Arizona Endurance Series
  urls:
    - https://example.com
    - https://example.com/details
```

This structure allows:
- **yaml2ics**: Treats the description as a plain multi-line string for .ics file generation
- **Jekyll**: Parses the YAML-formatted string content to display descriptions and URLs separately on the HTML calendar page

### Key Points
- `fat-biking.yml` is DEPRECATED - use `cycling-events.yml` instead
- YAML anchors and references are supported (e.g., `&anchor` and `*anchor`)
- The `yaml2ics` tool requires a file path as input (not stdin flags like `--help`)
- Generated `.ics` files are output to `data/calendars/`
- `cycling-events.yml` is also copied to `_data/cycling_events.yml` for Jekyll's data files feature

## Project Architecture

This is a Jekyll static site with the following structure:
- `_calendar/`: Calendar YAML sources
- `_data/`: Jekyll data files (includes cycling_events.yml copied from _calendar/)
- `data/`: Build outputs (calendars, Elm JS, GPX files, images)
- `elm/`: Elm applications for interactive features
  - `elm/cuesheet/`: Route cue sheet application
  - `elm/elevationprofile/`: Elevation profile visualization
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
    ↓ (Makefile copies)
_data/cycling_events.yml ──→ Jekyll reads for HTML page generation
    ↓ (yaml2ics converts)
data/calendars/cycling-events.ics ──→ Available for download
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

## Notes

- The site uses Jekyll with incremental builds enabled
- Markdown is processed with kramdown
- Jekyll plugins: jemoji, jekyll-sitemap
- Site URL: https://www.glyn.io
