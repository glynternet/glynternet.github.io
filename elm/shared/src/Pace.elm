module Pace exposing
    ( Options
    , Source(..)
    , defaultOptions
    , elapsedSoFar
    , formatSource
    , metresPerSecond
    , parseSource
    )

{-| The speed an arrival estimate runs at, from a set speed or the ride so far.
Position is measured in metres and elapsed time in seconds, including stops.
-}

import Time
import Wallclock


{-| Both a set speed and elapsed time are kept whichever source is active, so switching
sources does not throw away what was typed. The app supplies the point type; the arithmetic
does not need to resolve either endpoint.
-}
type alias Options point =
    { start : point
    , end : point
    , activePaceSource : Source
    , speedKmh : Float
    , elapsedAtStartSec : Float
    , rideStart : String
    }


{-| A set speed, or distance covered divided by elapsed time, entered directly or counted
from the start datetime. `FromRideStart` follows the clock without needing to retype a duration.

`rideStart` stays the raw value of a `datetime-local` input, rather than an instant. An empty
or unparseable value yields no pace.

-}
type Source
    = SetSpeed
    | FromElapsed
    | FromRideStart


{-| The app chooses the endpoints, normally the current route position and route end.
-}
defaultOptions : point -> point -> Options point
defaultOptions start end =
    { start = start
    , end = end
    , activePaceSource = SetSpeed
    , speedKmh = 20
    , elapsedAtStartSec = 0
    , rideStart = ""
    }


{-| Metres per second, or Nothing when there is not enough information for a positive speed.
The ride record requires only the current position and device clock, independently of app state.
-}
metresPerSecond : { ride | position : Maybe Float, now : Maybe Time.Posix, zone : Time.Zone } -> Options point -> Maybe Float
metresPerSecond ride options =
    case options.activePaceSource of
        SetSpeed ->
            ifPositive (options.speedKmh / 3.6)

        _ ->
            elapsedSoFar ride options |> Maybe.andThen (averageSoFar ride.position)


{-| Average elapsed speed, stops included, measured to the rider's position rather than the
chosen start point. Both distance and elapsed time must be positive to have a ride to average.
-}
averageSoFar : Maybe Float -> Float -> Maybe Float
averageSoFar position elapsedSeconds =
    Maybe.map2 (/)
        (position |> Maybe.andThen ifPositive)
        (ifPositive elapsedSeconds)


{-| Elapsed ride time, entered directly or counted from the start datetime. A set speed
has no elapsed time. Zero and negative elapsed times are retained here for the caller;
`metresPerSecond` rejects them as a basis for estimating speed.
-}
elapsedSoFar : { clock | now : Maybe Time.Posix, zone : Time.Zone } -> Options point -> Maybe Float
elapsedSoFar clock options =
    case options.activePaceSource of
        SetSpeed ->
            Nothing

        FromElapsed ->
            Just options.elapsedAtStartSec

        FromRideStart ->
            elapsedSinceRideStart clock options.rideStart


{-| Seconds between setting off and now, differencing local wall-clock times without a
timezone database. A span crossing a daylight-saving change is off by that hour: `Time.Zone`
converts an instant to local parts but does not expose the offset it used.
-}
elapsedSinceRideStart : { clock | now : Maybe Time.Posix, zone : Time.Zone } -> String -> Maybe Float
elapsedSinceRideStart clock rideStart =
    Maybe.map2
        (\setOff now -> toFloat (Wallclock.civilSeconds (Wallclock.localDateTime clock.zone now) - Wallclock.civilSeconds setOff))
        (Wallclock.parseLocalDateTime rideStart)
        clock.now


ifPositive : Float -> Maybe Float
ifPositive value =
    if value > 0 then
        Just value

    else
        Nothing


parseSource : String -> Maybe Source
parseSource s =
    case s of
        "speed" ->
            Just SetSpeed

        "elapsed" ->
            Just FromElapsed

        "rideStart" ->
            Just FromRideStart

        _ ->
            Nothing


formatSource : Source -> String
formatSource source =
    case source of
        SetSpeed ->
            "speed"

        FromElapsed ->
            "elapsed"

        FromRideStart ->
            "rideStart"
