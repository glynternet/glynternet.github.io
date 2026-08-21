module Format exposing
    ( bearing
    , climbRate
    , eleGainLoss
    , eleGainLossPercent
    , gradient
    , km
    , m
    , paceMinPerKm
    , percent
    , signedKm
    , signedM
    , speedKmh
    )

{-| Rendering figures in the units they are read in.

Every one of these takes a number in the app's own units — metres, metres per second, percent,
degrees from north — and hands back something to put on screen, so nothing here needs to know
what the figure was measured from.

-}

import List.Extra
import Round
import Wallclock



-- DISTANCE AND HEIGHT


km : Int -> Float -> String
km decimalPlaces metres =
    Round.round decimalPlaces (metres / 1000) ++ "km"


m : Float -> String
m metres =
    Round.round 0 metres ++ "m"


eleGainLoss : Float -> Float -> String
eleGainLoss gain loss =
    "↑" ++ m gain ++ " ↓" ++ m loss


signedM : Float -> String
signedM =
    withSign m << roundTo 0


signedKm : Int -> Float -> String
signedKm decimalPlaces =
    roundTo (decimalPlaces - 3) >> withSign (km decimalPlaces)



-- RATES AND PROPORTIONS


percent : Float -> String
percent pct =
    Round.round 0 pct ++ "%"


eleGainLossPercent : Float -> Float -> String
eleGainLossPercent gainPct lossPct =
    "↑" ++ percent gainPct ++ " ↓" ++ percent lossPct


gradient : Float -> String
gradient =
    roundTo 1 >> withSign (\pct -> Round.round 1 pct ++ "%")


climbRate : Float -> String
climbRate metresPerKm =
    Round.round 0 metresPerKm ++ "m/km"


speedKmh : Float -> String
speedKmh metresPerSecond =
    Round.round 1 (metresPerSecond * 3.6) ++ "km/h"


{-| A speed as the time it takes to cover a kilometre, which is the form a rider holding to a
pace thinks in.
-}
paceMinPerKm : Float -> String
paceMinPerKm metresPerSecond =
    Wallclock.minutesSeconds (round (1000 / metresPerSecond)) ++ "/km"



-- DIRECTION


{-| Compass bearing as degrees plus the nearest of the 16 compass points, e.g. "143° (SE)".
-}
bearing : Float -> String
bearing degreesFromNorth =
    let
        points =
            [ "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" ]
    in
    Round.round 0 degreesFromNorth
        ++ "° ("
        ++ (List.Extra.getAt (modBy 16 (round (degreesFromNorth / 22.5))) points |> Maybe.withDefault "N")
        ++ ")"



-- INTERNALS


{-| Signs a formatted value so a reader can tell "132m higher" from "132m lower" at a
glance. Round to the displayed precision first, so a value that displays as zero is not
given a misleading sign.
-}
withSign : (Float -> String) -> Float -> String
withSign format value =
    if value > 0 then
        "+" ++ format value

    else
        format value


roundTo : Int -> Float -> Float
roundTo decimalPlaces value =
    let
        factor =
            10 ^ toFloat decimalPlaces
    in
    toFloat (round (value * factor)) / factor
