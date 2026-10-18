# Elevation profile implementation review

The rendering plan is implemented, including the measured follow-up for position updates.
Unrelated updates skip profile content entirely. Ordinary static position changes reuse the
shared route preparation and both SVG layers in every segment, while updating distance labels
and the position marker. Correctness fixes were validated against the original build before
capturing the corrected performance baseline.

## Comparison with the plan

| Planned work | Implementation and evidence |
| --- | --- |
| Correct stale splits before caching | Off-route controls refresh segment membership, category boundaries and selection; GPS updates refresh chosen-position boundaries. Original-build regressions reproduced and the corrected build passed them. |
| Start with a coarse boundary | Implemented the proposed top-level `lazy7` first. Forty-five unrelated updates ran no content preparation. |
| Preserve segment references on position-only changes | Static fixed boundaries avoid WASM requests; chosen points compare effective distances; live view compares clamped ranges. Missing static segments still trigger a retry. |
| Measure before adding layers | With intensity on, coarse-cache position updates still spent 6.2–8.0 ms median in preparation. That justified the conditional follow-up. |
| Share full-route intensity | `ProfilePreparation` holds one transient result, keyed by explicit source revision and smoothing. Upload, track navigation and state import invalidate it; it is cleared when the profile is unmounted. |
| Keep stable SVG work independent of position | Each segment has two lazy groups: shading/ticks and waypoints/track. Dynamic distance labels stay between them and the position marker stays after them, preserving paint order. |
| Preserve layout dependencies | The waypoint layer receives the reserved marker-row height. A position-dependent tick test changed exactly two rows and rebuilt exactly those two waypoint layers. |
| Preserve storage and behavior | No new persisted fields. Old-save/new-build and new-save/old-build checks, upload, edits, export/import and reload passed. |

The final outer boundary is `lazy8`, adding the shared preparation record to the seven planned
inputs. This is the measured follow-up's explicit extra input, rather than a freshly assembled
record or captured function. Reference-dependent labels are derived inside it from route
distance; GPS metadata alone does not invalidate geometry.

`ProfileSplit` contains the small boundary/window helpers used by both construction and reuse
decisions. `ProfilePreparation` contains the existing intensity algorithm and full-route bounds;
neither module knows about app `State` or `Msg`. The app advances the transient source revision
on GPX responses, track navigation and state imports. Any future path replacing source
trackpoints must do the same.

## Measurements

The planned Congo Nile dataset has 15,345 trackpoints but no elevation values. The existing
WASM loader rejects it before profiling, so measurements used two supported real GPX routes:

| Dataset | Trackpoints | Segments | Seeded waypoint labels |
| --- | ---: | ---: | ---: |
| `Doom-4-20240328.gpx` | 9,488 | 3 | 3 |
| `Doom-1-20240328.gpx` | 8,140 | 1 | 33 |

The labels include an off-route cafe for filtering regressions; the denser case adds landmarks
to exercise label layout. Both datasets were loaded through the actual WASM parser. Runs used
headless Chromium, a 1440 × 1000 viewport, measured profile width of 1206 pixels, a clean browser
origin and blocked service workers. Served bundle hashes were verified. Each scenario repeated
45 interactions, with intensity both on and off. Instrumented execution counts and preparation
timings were collected separately from optimized builds without those counters.

The table below shows ordinary static position movement with intensity enabled. The event
measurement waits for **two animation frames**, so approximately 33 ms is its sampling floor,
not a claim that the app needs 33 ms to render. Browser scripting totals cover the whole batch,
including event handling, state serialization and updates, rather than profile work alone.

| Dataset | Build | Event median / p95 ms | Batch scripting ms |
| --- | --- | ---: | ---: |
| Doom 4 | Corrected baseline | 165.2 / 172.4 | 7150 |
| Doom 4 | Coarse cache | 33.4 / 50.0 | 1029 |
| Doom 4 | Final layers | 33.3 / 33.5 | 399 |
| Doom 1 dense | Corrected baseline | 121.6 / 132.9 | 5406 |
| Doom 1 dense | Coarse cache | 33.4 / 49.7 | 792 |
| Doom 1 dense | Final layers | 33.3 / 33.5 | 524 |

On Doom 4, instrumented position-update preparation fell from 8.0 ms median / 14.5 ms p95 in
the coarse version to 0.5 / 0.8 ms in the final version. The dense Doom 1 case fell from
6.2 / 14.1 ms to 0.3 / 0.9 ms. Across 45 ordinary position moves, intensity calculation,
sampling and both static SVG groups executed zero times; the corrected baseline requested 45
WASM splits and the final build requested none. Chosen-position boundary changes still request
the necessary split.

Unrelated updates also executed no profile preparation or static layers. Their two-frame
latency was already near the sampling floor in the baseline. Browser scripting totals for
these short scenarios varied across runs, so the robust result is the eliminated execution,
not a universal percentage speedup for every checkbox click.

Browser layout/style totals were small compared with scripting and remained small after the
change; the dense position batch, for example, recorded approximately 10 ms layout and 2 ms
style work across all 45 final-build interactions. Headless desktop measurements do not stand
in for timings on a rider's phone.

Raw timings, execution counts, layout/style totals, dataset details and bundle hashes are in
[profile-rendering-measurements.json](profile-rendering-measurements.json).

## Correctness checks

- `make route.js` and all 140 Elm tests pass, including 14 split-dependency and 11 preparation tests.
- Twenty-three SVG scenarios match the corrected baseline after removing only attribute-free
  grouping elements. Geometry, labels, styles, IDs, order and layout attributes are unchanged.
  The cases cover marker modes/references, live ends/unset position, chosen/category splits,
  intensity, sizing, waypoint deletion/edits and mobile width.
- Thirty-two browser dependency checks exercise cache hits/misses, fixed/chosen splits,
  GPS set/repeat/failure, manual clear, clamped live windows, filtering, resize, bad width
  reports, tab unmount/remount and recovery after a split error.
- Six source/layout checks cover real GPX upload, next/previous tracks, state import,
  position-dependent marker-row changes and clearing the reference. Prepared data and source
  revisions are absent from saved JSON.
- The actual storage bridge passes old-save/new-build restore, new-save/old-build restore,
  save/reload, export/import and fresh GPX upload. Relative, Pace, Cuesheet and Profile render.
- Execution instrumentation exists only in temporary browser-served copies, not `data/route.js`.

The browser driver and intermediate bundles used for comparisons are local artifacts under
`/tmp/profile-lazy-zhny9dc_`; the separate storage check is under
`/tmp/route-model-validation-sqsijobb`. The committed Elm tests and raw measurement report are
retained in the repository; those temporary browser drivers are not CI tests.

## Remaining work

The GPS persistence issue was left separate by this rendering change: a successful fix sanitized
its immediate storage write, but a later generic saved-control update could still save the live
GPS position. A subsequent fix now excludes GPS-derived positions in the shared encoder for
every save and state export; `elm/route/browser-tests/gps-persistence.cjs` covers the regression.

Live movement that changes the window, changed split boundaries, route edits and relevant
display changes correctly invalidate their dependent content. State serialization still runs
for saved controls and manual position updates. There is no claim that all work during a
position update has disappeared. Further caches or changes to persistence need their own
measurements and correctness checks.
