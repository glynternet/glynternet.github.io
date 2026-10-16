# Route App Module Extraction

`elm/route/src/Main.elm` is ~5,800 lines. The plan is not to break it up for its own sake —
the win is testability and blast radius, so each extraction below is worth doing only where it
leaves behind something that can be reasoned about, or tested, on its own.

Four are already done. `elm/shared/src/` now holds `Wallclock`, `Format`, `Ui` and `Pace` alongside
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

## 5. `Route` — the track model and the point vocabulary

**Impact:** High | **Effort:** High

`PointRef` (Main.elm:188) is the vocabulary for "a point on the route" — a waypoint, the
current position, or either end of the track — and every flow that asks the user to choose one
goes through it. It is the single most reused idea in the app and the best candidate for a
module of its own.

**The blocker:** `resolvePointRef` (:205) needs `EditableTrack`, which is the app's core track
model. Extracting `PointRef` therefore means extracting the track model with it:

| Type / function | Main.elm | Call sites in Main |
| --- | --- | --- |
| `EditableTrack` | 153 | 25 |
| `EditableWaypoint` | 160 | 11 |
| `WaypointOverrides` | 334 | — |
| `PointRef` | 188 | 27 |
| `resolvePointRef` | 205 | 9 |
| `effectiveWaypoint` / `effectiveWaypoints` | 359 / 391 | 6 |
| `selectableWaypoints` | 1997 | 10 |

Plus `refDistance` (:254), `shiftPointRef` (:263), `formatPointRef` / `parsePointRef`
(:302, :318), `selectedWaypointFor` (:2009), `sortPointRefs` (:749),
`editableTrackFromGpxTrack` (:346), `waypointDisplayName` (:5323), the three point names
(:283–294), and the `encodeEditableTrack` / `editableTrackDecoder` pair (:5563, :5591).

**What to do:** move the lot into a `Route` module (or a `Route.Track` / `Route.PointRef`
pair) in `elm/shared/src/`. Two snags to expect:

- `selectableWaypoints` and `selectedWaypointFor` take `State` today, only to read the
  category-filter fields. Same treatment as item 4: pass what they actually need.
- `unresolvedPointNotice` (:2023) is copy, not model. Leave it in `Main`.

**Why it is worth the effort:** the encode/decode pair is the format of everything the app
persists (see "Where route state is saved" in `CLAUDE.md`, including the compact trackpoint
encoding that keeps long routes inside browser storage limits). Round-tripping that is
currently untestable, and a regression in it silently breaks every saved route and every
shared state URL.

**Do this one on its own**, with nothing else in the commit, and check a real GPX still loads,
saves and reloads afterwards — not just that it compiles.
