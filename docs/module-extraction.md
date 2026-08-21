# Route App Module Extraction

`elm/route/src/Main.elm` is ~5,900 lines. The plan is not to break it up for its own sake —
the win is testability and blast radius, so each extraction below is worth doing only where it
leaves behind something that can be reasoned about, or tested, on its own.

Three are already done. `elm/shared/src/` now holds `Wallclock`, `Format` and `Ui` alongside
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

## 4. `Pace` — the arrival-estimate arithmetic

**Impact:** Medium | **Effort:** Low-Medium

The Pace tab's calculation currently takes the whole `State`:

| Function | Main.elm | Signature today |
| --- | --- | --- |
| `paceMetresPerSecond` | ~4214 | `State -> Maybe Float` |
| `averageSoFar` | ~4236 | `State -> Float -> Maybe Float` |
| `elapsedSoFar` | ~4246 | `State -> Maybe Float` |
| `elapsedSinceRideStart` | ~4266 | `State -> Maybe Float` |
| `ifPositive` | ~4274 | `Float -> Maybe Float` |

It only ever reads **four** fields: `state.pace`, `state.position`, `state.now`, `state.zone`.
Taking `State` hides that, and means the arithmetic cannot be exercised without building an
entire app state — which is why it has no tests today, despite being the part most worth
testing after `Wallclock`.

**What to do:** a `Pace` module in `elm/shared/src/` holding `PaceOptions` (Main.elm:451),
`PaceSource` (:474), `defaultPaceOptions` (:532), `parsePaceSource` / `formatPaceSource`
(:5530, :5546) and the five functions above, with the app's state replaced by an explicit
record:

```elm
metresPerSecond : { position : Maybe Float, now : Maybe Time.Posix, zone : Time.Zone } -> PaceOptions -> Maybe Float
```

This is a design change rather than a move, which is why it was not done alongside 1–3. Give
it its own commit.

**Then test it.** The cases are already known and were checked by hand against a running
build; they should be `elm-test` cases in `elm/route/tests/`:

- a set speed of 0, negative, and a normal value
- ride-so-far with no position set, with a position of 0, and with a normal position
- ride-so-far with 0 elapsed, negative elapsed, and a start datetime in the future
- a start datetime that is empty, half-typed (`2026-08`) or junk
- elapsed spanning midnight, several days, and a year boundary

**Leave behind:** `noPaceNotice` (:4447) and `rideSoFarNotice` (:4471) are user-facing copy,
not arithmetic. They stay in `Main` with the view.

**Known limitation to preserve and keep documented:** `elapsedSinceRideStart` differences two
wall-clock times with no timezone database, so a span crossing a daylight-saving change is out
by that hour. Immaterial next to the accuracy of a pace estimate; do not silently "fix" it by
changing behaviour without saying so. It is exactly fixable by round-tripping the zone offset
at the start instant if it ever matters.

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
