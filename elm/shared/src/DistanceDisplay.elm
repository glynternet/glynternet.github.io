module DistanceDisplay exposing (TotalDistanceDisplay(..), displayIsPercent, displayedDistanceValue, fromStartLabel, safePercent, waypointLabel)

{-| Shared distance values and labels for rendering and grouping. Kept outside
Main so display modes and their rounding can be tested without a browser.
-}

import Format
import GpxApi
import Route exposing (PointRef)


type TotalDistanceDisplay
    = FromZero
    | ToFinish
    | ToDistance
    | ToPoint PointRef
    | FromPoint PointRef
    | PercentProgress
    | PercentRemaining
    | None


displayedDistanceValue : TotalDistanceDisplay -> Float -> Float -> Maybe GpxApi.Waypoint -> Float -> Maybe Float
displayedDistanceValue mode finishDist referenceDistance refWaypoint distance =
    case mode of
        None ->
            Nothing

        FromZero ->
            Just distance

        ToFinish ->
            Just (finishDist - distance)

        ToDistance ->
            Just (referenceDistance - distance)

        ToPoint _ ->
            refWaypoint |> Maybe.map (\rw -> rw.distance - distance)

        FromPoint _ ->
            refWaypoint |> Maybe.map (\rw -> distance - rw.distance)

        PercentProgress ->
            safePercent distance finishDist

        PercentRemaining ->
            safePercent (finishDist - distance) finishDist


displayIsPercent : TotalDistanceDisplay -> Bool
displayIsPercent mode =
    case mode of
        PercentProgress ->
            True

        PercentRemaining ->
            True

        _ ->
            False


safePercent : Float -> Float -> Maybe Float
safePercent part total =
    if total > 0 then
        Just (part / total * 100)

    else
        Nothing


{-| The cuesheet suppresses the exact reference point's zero label. Absence
breaks grouping; it must never be treated as a shared empty label.
-}
waypointLabel : { options | totalDistanceDisplay : TotalDistanceDisplay, referenceDistance : Float, distanceDetail : Int } -> Float -> Maybe GpxApi.Waypoint -> GpxApi.Waypoint -> Maybe String
waypointLabel options finishDistance reference waypoint =
    displayedDistanceValue options.totalDistanceDisplay finishDistance options.referenceDistance reference waypoint.distance
        |> Maybe.andThen
            (\value ->
                if value == 0 then
                    Nothing

                else if displayIsPercent options.totalDistanceDisplay then
                    Just (Format.percent value)

                else
                    Just (Format.km options.distanceDetail value)
            )


{-| Pickers always show distance from the start, including zero.
-}
fromStartLabel : Int -> GpxApi.Waypoint -> Maybe String
fromStartLabel detail waypoint =
    Just (Format.km detail waypoint.distance)
