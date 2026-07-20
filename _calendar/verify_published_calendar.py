#!/usr/bin/env python3
"""Check that a built site actually contains the calendar generated from cycling-events.yml.

Jekyll does not fail when the generated data is missing: site.data.cycling_events is nil,
the page renders with `const eventsData = null`, and the build still exits 0. That would
silently publish an empty calendar, so the published output is checked against the source.
"""

import json
import re
import sys
from pathlib import Path

import yaml

SOURCE = Path(__file__).parent / "cycling-events.yml"


def ics_failure(ics_path: Path, expected: int) -> str:
    """Describe what is wrong with the published .ics, or an empty string if it is fine."""
    if not ics_path.is_file():
        return f"{ics_path} was not published"
    if (published := ics_path.read_text().count("BEGIN:VEVENT")) != expected:
        return f"{ics_path} holds {published} events, expected {expected}"
    return ""


def page_failure(page_path: Path, expected: int) -> str:
    """Describe what is wrong with the published calendar page, or an empty string if it is fine."""
    if not page_path.is_file():
        return f"{page_path} was not published"
    if not (embedded := re.search(r"const eventsData = (.+);", page_path.read_text())):
        return f"{page_path} does not embed an eventsData assignment"
    if not isinstance(events := json.loads(embedded.group(1)), list):
        return f"{page_path} embeds eventsData as {json.dumps(events)}, expected an array"
    if len(events) != expected:
        return f"{page_path} embeds {len(events)} events, expected {expected}"
    return ""


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <built-site-dir>", file=sys.stderr)
        sys.exit(1)

    site = Path(sys.argv[1])
    events = yaml.safe_load(SOURCE.read_text())["events"]

    # The .ics omits events explicitly marked as not attending; the page carries every
    # event and filters those out client-side instead.
    failures = [
        failure
        for failure in (
            ics_failure(
                site / "data/calendars/cycling-events.ics",
                sum(1 for event in events if event.get("attending") is not False),
            ),
            page_failure(site / "cycling/calendar.html", len(events)),
        )
        if failure
    ]

    if failures:
        for failure in failures:
            print(f"published calendar check failed: {failure}", file=sys.stderr)
        print("did `make calendars` run before the site was built?", file=sys.stderr)
        sys.exit(1)

    print(f"published calendar OK: {len(events)} events on the page")


if __name__ == "__main__":
    main()
