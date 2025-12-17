#!/usr/bin/env python3
"""Generate .ics calendar file from cycling-events.yml."""

import sys
from datetime import datetime, timedelta

import ics
import yaml


def build_description(event: dict) -> str:
    """Build ICS description from event fields."""
    parts = []

    if desc := event.get("description"):
        parts.append(desc)

    if series := event.get("series"):
        parts.append(f"Series: {series}")

    if urls := event.get("urls"):
        parts.append("Links:")
        for url in urls:
            parts.append(f"  {url}")

    return "\n".join(parts) if parts else ""


def create_event(event_data: dict) -> ics.Event:
    """Create an ics.Event from event data."""
    e = ics.Event()
    e.summary = event_data["summary"]

    # Handle dates - ics library expects datetime for all-day events
    begin = event_data["begin"]
    if isinstance(begin, str):
        begin = datetime.strptime(begin, "%Y-%m-%d").date()

    e.begin = begin
    e.make_all_day()

    # End date (optional, defaults to begin + 1 day for all-day events)
    if end := event_data.get("end"):
        if isinstance(end, str):
            end = datetime.strptime(end, "%Y-%m-%d").date()
        # ICS all-day events: end is exclusive, so add 1 day
        e.end = end + timedelta(days=1)
        e.make_all_day()

    if location := event_data.get("location"):
        e.location = location

    if description := build_description(event_data):
        e.description = description

    return e


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <yaml-file>", file=sys.stderr)
        sys.exit(1)

    yaml_file = sys.argv[1]

    with open(yaml_file, "r") as f:
        data = yaml.safe_load(f)

    calendar = ics.Calendar()

    for event_data in data.get("events", []):
        calendar.events.append(create_event(event_data))

    print(calendar.serialize())


if __name__ == "__main__":
    main()
