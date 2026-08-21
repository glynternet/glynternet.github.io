module Format exposing (paceMinPerKm, speedKmh)

{-| Rendering figures in the units they are read in.

Only the pace figures live here so far; the rest of the app's formatters are still in `Main`
and belong here too.

-}

import Round
import Wallclock


speedKmh : Float -> String
speedKmh metresPerSecond =
    Round.round 1 (metresPerSecond * 3.6) ++ "km/h"


{-| A speed as the time it takes to cover a kilometre, which is the form a rider holding to a
pace thinks in.
-}
paceMinPerKm : Float -> String
paceMinPerKm metresPerSecond =
    Wallclock.minutesSeconds (round (1000 / metresPerSecond)) ++ "/km"
