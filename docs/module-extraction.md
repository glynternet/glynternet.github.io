# Route App Module Extraction

`elm/route/src/Main.elm` is ~5,400 lines. The plan is not to break it up for its own sake —
the win is testability and blast radius, so each extraction below is worth doing only where it
leaves behind something that can be reasoned about, or tested, on its own.

All five are done. `elm/shared/src/` now holds `Wallclock`, `Format`, `Ui`, `Pace` and `Route` alongside
the older `GpxApi`, `Location` and `Zipper`. `elm/route/elm.json`'s `source-directories`
already points at `../shared/src`, so **a new module dropped in there needs no wiring**.

Verify any change here with `make route.js` (compiles to `data/route.js`) and `make elm-test`.
`data/route.js` is committed and is what actually ships — a source change that is not rebuilt
and committed does not reach the site.

## ~~1. `Wallclock` — times of day, durations, civil datetimes~~ ✅ Done

Commit `cb8464d`. Also brought `elm-test` into `elm.Dockerfile` and added
`elm/route/tests/WallclockTest.elm` (38 tests), the repo's first Elm tests.

## ~~2. `Format` — figures in the units they are read in~~ ✅ Done

Commit `44f78e1`. Names lost their `format` prefix: `Format.km`, `Format.eleGainLoss`,
`Format.bearing`.

## ~~3. `Ui` — the card primitives~~ ✅ Done

Commit `0ec2417`. All `Html msg` rather than `Html Msg`, so nothing in `Ui` knows what the
app's messages are.

## ~~4. `Pace` — the arrival-estimate arithmetic~~ ✅ Done

`elm/shared/src/Pace.elm` now owns the options, source selection, defaults, saved source
names and speed/elapsed-time calculations. `metresPerSecond` requires only a record with
`position`, `now` and `zone`, plus the pace options; `elapsedSoFar` needs only `now` and
`zone`, plus the options. Neither function depends on the app's `State`.

`Options point` takes the endpoint type as a parameter, so `Main` uses `Pace.Options PointRef`
without moving the route model. The app supplies the default endpoints to
`Pace.defaultOptions AtRoutePosition AtRouteEnd`. User-facing controls, notices and arrival
cards remain in `Main`, and the saved-state field names and source strings are unchanged.

`elm/route/tests/PaceTest.elm` covers set speeds, missing/non-positive distance and elapsed
time, invalid or future start datetimes, missing clocks, local timezone conversion, clock
updates, midnight/multi-day/year boundaries and the existing saved source names.

**Preserved limitation:** elapsed time from a start datetime differences local wall-clock
times without a timezone database, so a span crossing a daylight-saving change is off by
that hour. This remains documented on `Pace.elapsedSinceRideStart`.

## ~~5. `Route` — the track model and the point vocabulary~~ ✅ Done

`elm/shared/src/Route.elm` now owns the editable track/waypoint types, `PointRef`, effective
edits, stable indexed selections, point resolution and saved track encoding/decoding. `Main`
passes selection predicates to `Route.selectableWaypoints`, and passes position and location
explicitly to `Route.selectedWaypointFor`. The module has no dependency on app `State` or
`Msg`; live-view filtering, selection correction and user-facing notices remain in `Main`.

The stored track format is unchanged, including compact rounded trackpoints and support for
the older named-field encoding and waypoints without `created`. `RouteTest.elm` covers literal
saved-format fixtures, edit/creation/deletion round trips, multi-track zipper storage, point
resolution, category/off-route selection and stable waypoint indices.

Browser validation uses a real GPX (`data/nosoco24-0.gpx`, 3,112 trackpoints) with the actual
Elm bundle, WASM and IndexedDB code from `_layouts/route.html`. It verifies that the extracted
app restores a state saved by the previous build, persists edits across a reload, and writes
a state the previous build can still read. Rebuild and commit `data/route.js` with the source.
