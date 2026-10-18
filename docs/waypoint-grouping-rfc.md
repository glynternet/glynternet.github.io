# RFC: Group waypoints with the same displayed distance

## Status

Proposal. This describes a first implementation for the route app; it does
not change the current GPX or saved-state format.

The grouping criterion was confirmed on 18 October 2026: group waypoints when
their distances appear equal after rounding at the selected **Distance detail**.
This replaces the earlier proposal to group points within a fixed 50 m span.
The rendering and implementation details below remain proposals for review.

## Problem

Some GPX files contain several waypoints whose route distances look identical
at the selected detail. For example, points at 300 m and 304 m both display as
300 m when rounded to the nearest 10 m (`0.30km` in the current UI). Separate
rows make the cuesheet noisy and the waypoint list harder to scan, while the
individual names and categories may still be useful.

## Goals

- Make consecutive waypoints with the same displayed distance read as one
  location in the cuesheet and waypoint pickers.
- Make grouping follow the existing Distance detail setting.
- Preserve every waypoint, its name, categories, and editability.
- Make grouping deterministic and explainable.
- Avoid changing route distance, elevation, trackpoints, GPX import, or the
  stored representation of the original waypoints.

## Non-goals

- Automatically deleting or permanently merging waypoints.
- Adding a separate grouping-distance threshold or setting.
- Grouping by similar names or categories.
- Clustering arbitrary map points by zoom level.
- Changing the GPX export contract.

## Proposed behaviour

After applying waypoint edits and filters, derive display groups from the
effective waypoints in route order. A group is a maximal consecutive run whose
members all have the same rounded distance label. Compare the values each
waypoint would display individually, before grouping. Start a new group as soon
as that label changes.

Use the same distance value, units and rounding function as the view displaying
the group. In the current from-start kilometre display this is
`Format.km cs.distanceDetail waypoint.distance`. Distance detail selects 0–3
decimal places in kilometres: nearest kilometre, 100 m, 10 m or metre.

Examples with distances measured from the route start:

| Waypoint distances | Distance detail | Individual labels | Result |
| --- | --- | --- | --- |
| 300 m, 304 m | 2 (10 m) | `0.30km`, `0.30km` | One group |
| 300 m, 304 m | 3 (1 m) | `0.300km`, `0.304km` | Separate rows |
| 304 m, 306 m | 2 (10 m) | `0.30km`, `0.31km` | Separate rows |
| 300 m, 304 m, 308 m | 2 (10 m) | `0.30km`, `0.30km`, `0.31km` | First two grouped; third separate |

Recompute groups whenever Distance detail changes. Coarser detail can combine
groups; finer detail can split them. Use the formatter's existing rounding
rules, including its treatment of exact rounding boundaries.

Compare each waypoint's displayed distance, not the rounded gap between points.
A gap displayed as zero does not establish that the two waypoint distance
labels are equal. Do not use a fixed proximity threshold or chain together
points merely because each neighbouring pair is close.

Use distance along the route rather than straight-line distance. Deleted
waypoints are excluded; remaining items retain the view's route order after
distance overrides have been applied.

### Display modes

The cuesheet can show distance from the start, distance to the finish or a
reference point, percentages, or no total distance. The implementation proposal
is to derive the comparison label through the same display-mode conversion and
formatter used for an individual row. For distance modes, apply Distance detail
after that conversion. For percentage modes, use the displayed percentage's
precision. Changing the mode or reference can therefore change groups too.

An absent label is not a shared distance: if the mode hides distances or its
reference cannot be resolved, leave those waypoints ungrouped. A reference
point whose zero label is suppressed likewise remains separate. This avoids
combining every row merely because none has a distance label.

Waypoint pickers currently show from-start distances at a fixed one decimal
place. Update their distance labels to use Distance detail, and derive their
groups from those same from-start labels. Each view's grouping must agree with
the distances it actually shows.

### Group rows and selection

Singletons render as they do today. A group of two or more renders as one
location row with a de-duplicated ` · `-joined label, the shared rounded distance
and the member names/categories available in an expanded detail view. Use the
first member's unrounded route distance and cumulative gain/loss as the
representative values; do not average or overwrite members' original values.
The first version should default groups to expanded, so no information is
hidden. Later, a per-view collapse preference could be added.

Selectors should continue selecting individual members. The group label is
context only and must not replace the underlying `PointRef`.

## Data and implementation

Keep `EditableWaypoint` and `GpxApi.Waypoint` unchanged. Add a derived type in
`elm/route/src/Main.elm`, for example:

```elm
type alias WaypointGroup =
    { members : List ( Int, GpxApi.Waypoint )
    , distance : Float
    , gain : Float
    , loss : Float
    }
```

Implement a pure grouping function that accepts the view's distance-label
function instead of a proximity threshold, for example:

```elm
groupWaypoints :
    (GpxApi.Waypoint -> Maybe String)
    -> List ( Int, GpxApi.Waypoint )
    -> List WaypointGroup
```

Consecutive `Just` labels that are equal form one group; a `Nothing` label
produces a singleton and breaks the run. Share the label calculation with row
rendering, using `displayedDistanceValue` and the existing `Format` functions
where appropriate, so rounding cannot drift between grouping and display.
Compare the formatted labels directly rather than introducing separate
floating-point tolerances or reimplementing rounding.

The function consumes effective waypoints with stable editable-list indices,
so grouping never changes indices used by `AtWaypoint`, deletion, or editing
messages.

Use the same effective waypoint source as the existing cuesheet and selectors.
Group at the presentation boundary, after filtering and distance overrides have
been resolved. Do not serialize derived groups or rounded member distances.
The existing saved Distance detail setting determines groups again when a view
is restored; no new grouping setting or saved-state migration is needed.

## Rendering and interaction

Refactor `waypointInfos`/cuesheet row construction to consume groups. Keep
`PointRef` member identity intact for selecting start/end points, editing names,
and toggling categories. An expanded group can render a nested list whose
controls dispatch the original member index.

Announce the number of grouped waypoints accessibly and retain every member
name in visible text or an accessible label. For duplicate or empty names, use
a fallback such as `2 waypoints` rather than an empty label.

## Edge cases

- A deleted or filtered waypoint must not keep adjacent visible points apart
  or become an unexplained group member.
- Equal displayed distances should form one group, including three or more
  members, even when their underlying distances differ.
- Distinct labels stay separate even across a very small gap or with identical
  names. Nonconsecutive matching labels do not merge across intervening rows.
- Distance overrides can change ordering and grouping, so use effective
  distances while preserving original member indices.
- Changing detail, display mode or reference must recompute groups without
  losing the selected member or changing stored waypoint values.
- Route start/end synthetic points and the current-position row are not GPX
  waypoints and are not grouped with them; keep their individual identities.

## Testing

Add unit tests for empty and singleton input; equal-distance groups; all four
examples above; and values below, at and above rounding boundaries using the
existing formatter's results. Cover every supported Distance detail value and
verify that a chain of small gaps cannot merge different labels.

Cover distance-mode/reference changes, percentage labels, absent labels,
deleted/filtered members, distance overrides, stable original indices, and
duplicate/empty display names. Verify the group representative retains the
first member's unrounded distance and cumulative gain/loss, with every member's
original values intact.

Add a view-level fixture with waypoints at 300 m and 304 m. At detail 2, verify
one grouped location labelled `0.30km`, with both members individually
selectable and editable. Change to detail 3 and verify separate `0.300km` and
`0.304km` rows; change back and verify they regroup without losing selection.
Repeat for picker labels, and verify that a saved-state round trip restores
the selected detail and resulting groups without storing the groups themselves.

## Rollout

1. Share the displayed-distance label calculation between rendering and the
   pure grouping function, and add tests.
2. Refactor cuesheet rendering behind derived groups.
3. Add expanded member rendering and accessibility text; align picker labels
   and grouping with Distance detail.
4. Verify detail changes, selectors, edits, saved-state round trips, and GPX
   export.
5. Run the repository Elm test/build commands and inspect a GPX containing
   waypoints with equal rounded distances and points across a rounding boundary.
