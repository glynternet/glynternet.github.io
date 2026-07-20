#!/usr/bin/env python3
"""Generate .ics calendar file from cycling-events.yml."""

import re
import sys
from datetime import datetime, timedelta, date

import ics
import yaml


def event_uid(event_data: dict) -> str:
    """Build a UID that stays the same across rebuilds.

    Calendar clients key events by UID, so a UID that changed every build would make
    subscribers delete and recreate every event on each deploy. Deriving it from the
    summary and start year keeps it stable, and means an event moved within its year
    is seen as moved rather than replaced.
    """
    return f"{re.sub(r'[^a-z0-9]+', '-', event_data['summary'].lower()).strip('-')}-{event_data['begin'].year}@glyn.io"


def build_description(event: dict, series_map: dict) -> str:
    """Build ICS description from event fields."""
    parts = []

    if desc := event.get("description"):
        parts.append(desc)

    if series := event.get("series"):
        series_info = series_map.get(series, {})
        if series_url := series_info.get("url"):
            parts.append(f"Series: {series} ({series_url})")
        else:
            parts.append(f"Series: {series}")

    if urls := event.get("urls"):
        parts.append("Links:")
        for url in urls:
            parts.append(f"  {url}")

    return "\n".join(parts) if parts else ""


def create_event(event_data: dict, series_map: dict) -> ics.Event:
    """Create an ics.Event from event data."""
    e = ics.Event()
    e.summary = event_data["summary"]
    if series := event_data.get("series"):
        e.summary += f" ({series})"

    # Handle dates - ics library expects datetime for all-day events
    if "begin" not in event_data or not isinstance(event_data["begin"], date):
        print(f"'begin' key expected to be a date in event: {event_data}", file=sys.stderr)
        sys.exit(1)
    e.begin = event_data["begin"]

    # Built from the raw summary, not e.summary, so renaming a series doesn't change the UID
    e.uid = event_uid(event_data)

    # End date (optional, defaults to begin + 1 day for all-day events)
    if end := event_data.get("end"):
        if not isinstance(end, date):
            print(f"optional 'end' key expected to be a date in event: {event_data}", file=sys.stderr)
        # ICS all-day events: end is exclusive, so add 1 day
        e.end = end + timedelta(days=1)

    e.make_all_day()

    if location := event_data.get("location"):
        e.location = location

    if geo := event_data.get("geo"):
        if not isinstance(geo, dict) or set(geo.keys()) != {"lat", "lon"}:
            print(f"'geo' must be a mapping with exactly 'lat' and 'lon' keys in event: {event_data}", file=sys.stderr)
            sys.exit(1)
        if not all(isinstance(geo[k], (int, float)) for k in ("lat", "lon")):
            print(f"'geo' lat/lon must be numeric in event: {event_data}", file=sys.stderr)
            sys.exit(1)
        e.geo = (geo["lat"], geo["lon"])

    if description := build_description(event_data, series_map):
        e.description = description

    return e


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <yaml-file>", file=sys.stderr)
        sys.exit(1)

    yaml_file = sys.argv[1]

    with open(yaml_file, "r") as f:
        data = yaml.safe_load(f)

    series_map = data["series"]
    calendar = ics.Calendar()
    seen_uids = set()

    for event_data in data.get("events", []):
        if event_data.get("attending") is False:
            continue
        event = create_event(event_data, series_map)
        if event.uid in seen_uids:
            print(f"duplicate UID '{event.uid}' generated for event: {event_data}", file=sys.stderr)
            sys.exit(1)
        seen_uids.add(event.uid)
        calendar.events.append(event)

    print(calendar.serialize())


if __name__ == "__main__":
    main()
