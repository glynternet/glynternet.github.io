# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a calendar generation subdirectory within a Jekyll-based static website (glynternet.github.io). The `_calendar` directory contains YAML event definitions that are converted to iCalendar (.ics) format for embedding in the website.

## Build Commands

### Building Calendar Files
```bash
# Build all calendars (generates .ics files in ../data/calendars/)
make all

# Build specific calendar
make fat-biking    # Generates ../data/calendars/fat-biking.ics
make bike-events   # Generates ../data/calendars/bike-events.ics
```

### Parent Directory Build Commands
From the parent directory (`..`), you can:
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

Calendar events are defined in YAML files (`bike-events.yml`, `fat-biking.yml`) and converted to iCalendar format using the `yaml2ics` tool.

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
      urls:
        - https://example.com
```

### Key Points
- `fat-biking.yml` is DEPRECATED - use `bike-events.yml` instead
- YAML anchors and references are supported (e.g., `&anchor` and `*anchor`)
- The `yaml2ics` tool requires a file path as input (not stdin flags like `--help`)
- Generated `.ics` files are output to `../data/calendars/`

## Project Architecture

This is a Jekyll static site with the following structure:
- `_calendar/`: Calendar YAML sources (this directory)
- `data/`: Build outputs (calendars, Elm JS, GPX files, images)
- `elm/`: Elm applications for interactive features
  - `elm/cuesheet/`: Route cue sheet application
  - `elm/elevationprofile/`: Elevation profile visualization
- `_pages/`: Jekyll page content
- `_layouts/`: Jekyll templates
- `_includes/`: Jekyll partials
- `_sass/`: Stylesheets

## Development Workflow

1. Edit YAML calendar files in `_calendar/`
2. Run `make all` to regenerate `.ics` files
3. Commit both YAML and generated `.ics` files
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
