# RFC: Group waypoints with the same displayed distance

## Status

Implemented on 19 October 2026. Grouping uses the selected Distance detail in
the cuesheet and waypoint pickers, with expanded member rows and individual
selection/editing. The GPX and saved-state formats are unchanged.

The grouping criterion was confirmed on 18 October 2026: group waypoints when
their distances appear equal after rounding at the selected **Distance detail**.
This replaces the earlier proposal to group points within a fixed 50 m span.

On 19 October 2026 the user confirmed that the RFC looks good and requested
that grouping live in a separate, easily unit-tested module accepting a
`Waypoint -> Maybe String` callback. The implementation and testing plan below
records that requirement. The zero-gap question remains a follow-up consideration.

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
Do not use a fixed proximity threshold or chain together points merely because
each neighbouring pair is close.

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

Waypoint pickers show from-start distances using Distance detail and derive
their groups from those same labels. Native option groups provide context while
each member remains selectable. Each view's grouping agrees with the distances
it actually shows.

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

Keep `EditableWaypoint` and `GpxApi.Waypoint` unchanged. Put the grouping type
and algorithm in a separate local module, `elm/shared/src/WaypointGrouping.elm`,
exposing `WaypointGroup` and `groupWaypoints`. This follows the existing shared
module layout and is directly importable by `elm-test` through the route app's
existing source directories.

The module must be independent of `Main`, app state, HTML/SVG, ports and browser
APIs. Its inputs are the supplied label function and an ordered list of indexed
effective waypoints; its output is the derived groups. For example:

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

`Main` supplies the label function with the current display settings captured
in it, then renders the returned groups. Keep the shared label calculation
pure and importable too, so tests can exercise the actual display-mode and
rounding logic without importing `Main` or starting the application. The
grouping module itself only compares the callback's results; it has no
knowledge of distance detail, display modes or formatting rules.

The caller resolves edits, excludes deleted/filtered/synthetic points and
orders the effective waypoints before calling the function. The function
preserves that input order and the stable editable-list indices, so grouping
never changes indices used by `AtWaypoint`, deletion, or editing messages.

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

Unit tests are the primary verification for grouping. Add
`elm/route/tests/WaypointGroupingTest.elm`, importing `WaypointGrouping`
directly and running under the existing `make elm-test` target. Tests pass
small waypoint fixtures and a `GpxApi.Waypoint -> Maybe String` callback
straight to `groupWaypoints`; no browser or application startup is required.

Test the grouping contract with simple supplied callbacks: empty and singleton
input; consecutive equal `Just` labels; differing labels; nonconsecutive
matching labels; and `Nothing` producing a singleton and breaking the run,
including consecutive `Nothing` values. Verify that the supplied labels control
grouping even when the underlying waypoint distances differ. Assert exact
member order, stable original indices and preservation of every waypoint;
the representative must retain the first member's unrounded distance and
cumulative gain/loss.

Then use the real shared label/formatting helpers in unit tests for all four
examples above, values below/at/above rounding boundaries, every supported
Distance detail value, display-mode/reference changes, percentages and absent
labels. Calling the function again with detail 3 and then detail 2 must split
and regroup the 300 m/304 m fixture. Verify that a chain of small gaps cannot
merge different labels. Test the effective-waypoint preparation and display
helpers for deleted/filtered members, distance overrides and duplicate/empty
display names.

Keep browser coverage to a small integration smoke test with the 300 m/304 m
fixture: changing Distance detail updates the rendered cuesheet and picker
groups, both members remain selectable/editable, selection survives regrouping,
and restoring saved state restores the detail and resulting groups. The rounding
and grouping edge-case matrix belongs in the unit suite.

## Follow-up consideration: gaps displayed as zero

At the user's request on 18 October 2026, retain this for follow-up review:
a gap displayed as zero does not establish that the two waypoint distance
labels are equal. For example, at detail 2 the 2 m gap between 304 m and 306 m
displays as `0.00km`, while the waypoint labels are `0.30km` and `0.31km`.

Consider whether such waypoints should also be grouped, or whether their
display needs another treatment. This is deferred for later consideration;
the current proposal and its acceptance checks use matching waypoint distance
labels. No additional grouping rule is decided here.

## Rollout

1. Add `WaypointGrouping.elm` and its direct unit tests; make the shared
   displayed-distance label calculation independently testable as well.
2. Refactor cuesheet rendering behind derived groups.
3. Add expanded member rendering and accessibility text; align picker labels
   and grouping with Distance detail.
4. Verify detail changes, selectors, edits, saved-state round trips, and GPX
   export.
5. Run the repository Elm test/build commands and the focused browser
   integration smoke test.

## Implementation and verification, 19 October 2026

- `WaypointGrouping.elm` owns the pure callback-based grouping function and
  group labels. It preserves input order, original indices and unrounded values.
- `DistanceDisplay.elm` owns the distance-display modes and shared label
  calculation. `Main` supplies the current options to that calculation.
- `CuesheetRows.elm` prepares expanded group/member rows and ride intervals.
  Synthetic position and endpoint identities remain separate even when their
  distances coincide with actual waypoints. Ride intervals use the first
  members' unrounded representative values.
- Pickers use native `optgroup` elements with individually selectable options.
  Member editing remains in the Waypoints tab. Category filtering preserves
  original indices before display-only category trimming.
- The 170-test Elm suite passed under `elm-test 0.19.1-revision12`; the
  optimized application build passed with Elm 0.19.1. The grouping and row
  preparation cases run directly in the unit suite.
- `elm/route/browser-tests/waypoint-grouping.cjs` uses synthetic state with the
  actual Elm bundle, page adapters, WASM and IndexedDB. It verifies detail
  changes, individual selection/editing, saved-state restore preserving both
  members, and unchanged split-GPX track output. The existing split-GPX exporter
  writes tracks only; waypoint records remain in saved state. The zero-gap
  follow-up above remains deferred.
