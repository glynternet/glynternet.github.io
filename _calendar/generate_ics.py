#!/usr/bin/env python3
"""Generate .ics calendar file from cycling-events.yml."""

import sys
from datetime import datetime, timedelta, date

import ics
import yaml


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

    # End date (optional, defaults to begin + 1 day for all-day events)
    if end := event_data.get("end"):
        if not isinstance(end, date):
            print(f"optional 'end' key expected to be a date in event: {event_data}", file=sys.stderr)
        # ICS all-day events: end is exclusive, so add 1 day
        e.end = end + timedelta(days=1)

    e.make_all_day()

    if location := event_data.get("location"):
        e.location = location

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

    for event_data in data.get("events", []):
        calendar.events.append(create_event(event_data, series_map))

    print(calendar.serialize())


if __name__ == "__main__":
    main()
