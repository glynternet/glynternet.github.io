# Elevation profile rendering plan

Reduce repeated profile calculations and virtual DOM construction while keeping route geometry,
labels, position tracking and saved-state behavior correct. Start with one lazy boundary around
profile preparation and rendering. Add finer boundaries only where measurements show a useful
remaining cost.

This implements performance item C in `todo/optimise.md`. A/B already downsample the line and
intensity stops; their historical Firefox profile is context, not a measurement of this build.

Implemented with the measured layer follow-up. See [implementation review and measurements](profile-rendering-results.md)
for the comparison against this plan, validation, dataset substitution and remaining work.

## Current behavior and constraints

`viewElevationProfileTab` computes elevation bounds, full-route intensity, segment sampling and
distance markers during every view evaluation. Its call to `profile` has 16 arguments, including
freshly constructed records, lists and an optional segment-local position. Wrapping that call
directly in `lazy` would leave much of the preparation outside the cache and invalidate it often.

Elm compares a lazy node's function and arguments with JavaScript reference equality. Existing
track, split-result and option records can retain their references across unrelated updates.
Fresh records, nonempty lists, `Just` wrappers and captured functions can prevent reuse even when
their contents are equal. A lazy node reuses its previous subtree at that location; unmounting
the profile when another tab opens discards that subtree.

The profile has several dependencies that must remain explicit:

| Input | Affected output |
| --- | --- |
| Trackpoints and segment data | Line geometry, elevation bounds, totals, waypoint placement and intensity |
| Measured container width | Line and intensity sampling budgets |
| Font size, track height, thickness and label-height gain | Geometry and SVG layout |
| Intensity toggle and smoothing distance | Shading and its route-wide normalization |
| Cuesheet distance mode, precision and reference | Distance markers, their labels and the reserved label row |
| Current position | Position marker, live window, position-based split boundaries and position-based distance labels |
| Off-route threshold | Waypoint stroke and label colors |

Preserve full-resolution trackpoints for elevation lookups, cumulative gain/loss and the existing
intensity calculation. Preserve route-wide intensity normalization, segment-local distances,
gradient IDs, SVG paint order and the profile container's resize-observer behavior.

## Establish the baseline

Use the optimized build at `3362bf2`, a fixed browser/viewport and disabled extensions. Exercise
`data/congo-nile-trail.gpx` and a route with several segments and enough waypoint labels to expose
layout costs. Enable intensity for one run and leave it disabled for another.

Use a clean browser origin or bypass the service worker, and verify the served bundle for each
comparison. Its cache-first policy can otherwise keep running an older build during measurement.

Measure unrelated updates while the profile remains mounted, ordinary position movement,
position-dependent splits, live-window movement, resize and relevant display-option changes.
Use an actual unrelated control such as show-off-route-distance; tab switching unmounts the
profile and is not a valid cache-reuse test.

Count profile preparation executions and WASM split requests with temporary instrumentation.
Record interaction-to-next-frame timing and browser scripting/layout/paint costs separately in
an uninstrumented optimized build. Use the same interaction sequences before and after, repeat
them, and report median and p95 values alongside route size, segment count and viewport width.
Do not use unchanged DOM nodes alone as evidence that calculations were skipped.

## Correct split dependencies first

Audit and fix existing split invalidation before suppressing any requests. Two current paths
can leave stale segment data:

- Successful GPS updates do not request static splits, including a chosen `AtRoutePosition`
  boundary whose effective distance changes with the fix.
- `UpdateOffRouteThreshold` and `UpdateShowOffRouteWaypoints` only store state, although static
  and live segment construction applies those filters to waypoint membership. Category-based
  split boundaries can change as a consequence too.

Route off-route filter changes through split refresh and the existing selection-correction
policy. Refresh static WASM segments or local live segments as appropriate, including any
category-derived boundaries. A threshold change still updates waypoint colors when membership
is unchanged. Refreshing conservatively on these filter changes is acceptable; optimize their
frequency only after correctness is covered.

Add focused regressions for GPS set/move of a chosen-position split, off-route hiding on/off,
and a threshold crossing a waypoint's off-route distance in both static and live views. Include
category splits with that waypoint's category selected. Check segment membership, boundary
distances, labels and selection behavior immediately after the change, without an extra manual
position update. Merely adding lazy arguments cannot repair stale segment data.

Keep these correctness corrections separate from the rendering optimization. Retain the
original measurements as context, then establish the corrected build as the comparison baseline
for caching. Existing stale output is not the expected result for before/after visual checks.

## Add a coarse lazy boundary

Keep `viewElevationProfileTab` as the small mounted shell and place all existing preparation
inside a top-level `viewProfileContent` function. Pass existing records directly:

```elm
Html.Lazy.lazy7 viewProfileContent
    tracks.current
    splitResult
    state.elevationProfile
    state.cuesheet
    width
    state.position
    state.offRouteThreshold
```

`width` is the measured pixel width with the existing 500-point fallback. The wrapper takes an
`EditableTrack`, `GpxApi.SplitResult`, the two existing option records, an `Int`, a `Maybe Float`
and a `Float`. It does not receive `State`, construct a new input record, or capture arguments in
an anonymous/partially applied function. Keep the live-position warning outside this boundary.

Move min/max scans, intensity calculation and normalization, per-segment filtering/sampling,
reference resolution and marker generation inside `viewProfileContent`. Compute full-route
intensity once per content evaluation, then use it for every segment as today. Resolve the
profile's reference point from the supplied position and track; distance labels use its route
distance, not the GPS fix's off-route metadata. Cover that assumption in the browser checks.

The first boundary intentionally invalidates for changed position or either option record. An
unrelated cuesheet-only option can therefore cause a conservative miss; do not introduce stored
option snapshots simply to eliminate every possible miss. Verify that genuinely unrelated
updates reuse the content and execute none of the preparation above.

Keep this change focused on rendering. Do not change the saved state, add a persisted cache,
alter sampling/intensity algorithms, or introduce a general memoization framework.

## Preserve segment references during position updates

Manual `UpdatePosition` currently uses `updateSplitAndStore`, requesting a new static WASM split
even if its boundaries are unchanged. Decoding the result replaces every segment reference.
Avoid those requests with a narrow decision for position-only changes:

| View and split mode | Position-only behavior |
| --- | --- |
| Static equidistant | Keep the existing split result |
| Static categories | Keep the existing split result |
| Static chosen points | Compare old/new effective `splitDistances`; request a split only if they differ |
| Live | Rebuild the local window when its effective range changes; preserve it when the range and other inputs are unchanged |

Scope this decision to manual movement/clear and successful GPS updates. Route edits, corrected
filter handlers, split settings and switching static/live modes continue to invalidate their
dependent segments. Compare the small boundary-distance lists when needed, rather than
deep-comparing trackpoints or serializing an entire split request to use as a key.

Keep manual positions persistent and clear stale GPS metadata on manual changes. Preserve the
successful GPS handler's sanitized storage write, which clears position in the saved value.
Do not reuse `updateSplitAndStore` directly in that handler: it would immediately persist the
live GPS position. A failed GPS request must not move the marker or replace segment data.
Repeated GPS fixes at the same matched distance should preserve the existing optional position
reference when possible, while allowing the fix metadata to update.

There is a separate existing persistence issue: later generic `updateAndStoreModel` writes can
save the GPS-derived position still held in live state. Fixing that broader behavior belongs
in a separate correctness change with a GPS-fix, unrelated-control-change, reload regression;
this performance change must preserve the GPS handler's immediate sanitized write.

The corrected GPS path must follow the same boundary-dependency decision as manual movement.
Never retain stale boundaries to improve cache-hit counts. Clearing a position must remove
that split boundary when appropriate.

## Decide whether to separate the position marker

After the coarse cache and position-update decision, repeat the measurements. If ordinary
position movement still spends material time preparing/rendering unchanged profile content,
add a focused follow-up that separates the position marker from stable SVG content. Otherwise
stop with the simpler implementation and record the measured result.

For that follow-up, keep the marker in the same SVG coordinates and paint order. Cache stable
line, ticks, waypoints and shading independently of position. The marker consumes position and
the layout/elevation inputs it actually needs. Distance labels get a separate boundary if they
depend on `AtRoutePosition`; moving the rider must still update those labels even when static
geometry is reusable. Live movement can legitimately invalidate geometry because the window
and its segment-local coordinates change.

Position-dependent distance markers can also appear or disappear, changing the reserved label
row and overall SVG height. Waypoint text placement, stroke bottoms and the position marker
must share that layout and invalidate when its scalar dimensions change. Test position
set/clear and movement across a tick interval, not just changes to label text.

Do not pass freshly generated coordinate calculators, downsampled records, intensity lists or
marker lists into inner lazy calls. Supply stable source references and scalar settings, and
perform their derivations inside the relevant function. Avoid an unconditional SVG overlay or
a separate cache for each element before measuring the simpler boundaries.

Full-route intensity must still be calculated once for the route, not once per segment as an
accidental consequence of layering. If sharing that result across independent layers requires
additional storage, design one bounded transient preparation cache keyed by an explicit source
revision and smoothing distance. Advance the revision when source data changes; Elm's ordinary
equality operator must not deep-compare trackpoints as a substitute for a reference check.
Keep the cache out of saved state and clear/rebuild it on imports and source changes. Treat
that as part of the measured follow-up, including its invalidation tests, rather than silently
adding it to the first lazy wrapper.

## Verify correctness and reuse

Run `make route.js`, `make elm-test` and `git diff --check`. Add focused tests for the new
position-dependent split decision, including set/move/clear, unchanged effective boundaries,
and manual/GPS paths, plus the filter-dependency regressions above. Keep helper extraction
limited to what makes those decisions testable.

Browser checks must use the actual Elm bundle, WASM and storage bridge. Compare SVG geometry,
marker positions, labels, shading and layout before/after for:

- Static equidistant, chosen-waypoint, chosen-position and category splits, including multiple segments.
- Live view before a position is set and while moving near the route's start and finish.
- Distance and percentage markers, references to a waypoint, current position and route ends.
- Intensity on/off, smoothing changes, waypoint edits/deletion and off-route coloring.
- Resize, tiny/detached-container width reports, and tab unmount/remount.
- GPX upload, imported state, and save/reload without any new persisted fields.

Use temporary execution counters to verify a cache hit on an unrelated update, a miss on each
relevant input change, and unchanged static split requests when position does not affect the
boundaries. A new record with equal contents is allowed to miss; an obsolete view is never
allowed to hit. Remove instrumentation before the optimized timing comparison.

Keep the change if it eliminates the targeted repeated work and improves measured interaction
cost without a material regression in the scenarios that correctly invalidate. Report coarse
cache results separately from any later marker/layer work. Commit regenerated `data/route.js`
with the implementation, update item C with the measured scope, and retain any deferred work
explicitly instead of marking all position-update costs solved.

The implementation semantics are documented in the [Elm optimization guide](https://guide.elm-lang.org/optimization/lazy)
and the [Html.Lazy source](https://github.com/elm/html/blob/1.0.0/src/Html/Lazy.elm).
