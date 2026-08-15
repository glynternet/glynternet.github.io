module Location exposing (LatLon, LocationError(..), LocationState, bearing, decodeLocationResult, findNearestTrackPoint, haversineDistance, locationErrorToString)

import GpxApi
import Json.Decode


type alias LatLon =
    { lat : Float
    , lon : Float
    }


type alias LocationState =
    { position : LatLon
    , accuracy : Float
    , matchedDistance : Float
    , offRouteDistance : Float
    }


type LocationError
    = PermissionDenied
    | PositionUnavailable
    | GeoTimeout


haversineDistance : LatLon -> LatLon -> Float
haversineDistance a b =
    let
        r =
            6371000

        toRad deg =
            deg * pi / 180

        dLat =
            toRad (b.lat - a.lat)

        dLon =
            toRad (b.lon - a.lon)

        sinDLat =
            sin (dLat / 2)

        sinDLon =
            sin (dLon / 2)

        h =
            sinDLat * sinDLat + cos (toRad a.lat) * cos (toRad b.lat) * sinDLon * sinDLon
    in
    2 * r * asin (sqrt h)


{-| Initial great-circle bearing from `a` to `b`, as a compass bearing in degrees
(0 = north, clockwise). Note this is the bearing at the start of the path: over a long
distance a great circle curves, so arriving at `b` you would be pointing elsewhere.
-}
bearing : LatLon -> LatLon -> Float
bearing a b =
    let
        toRad deg =
            deg * pi / 180

        dLon =
            toRad (b.lon - a.lon)

        y =
            sin dLon * cos (toRad b.lat)

        x =
            cos (toRad a.lat) * sin (toRad b.lat) - sin (toRad a.lat) * cos (toRad b.lat) * cos dLon

        degreesFromNorth =
            atan2 y x * 180 / pi
    in
    -- atan2 gives (-180, 180]; compass bearings run 0-360
    if degreesFromNorth < 0 then
        degreesFromNorth + 360

    else
        degreesFromNorth


findNearestTrackPoint : LatLon -> List GpxApi.TrackPoint -> Maybe GpxApi.TrackPoint
findNearestTrackPoint pos trackpoints =
    trackpoints
        |> List.map (\tp -> ( haversineDistance pos (LatLon tp.lat tp.lon), tp ))
        |> List.sortBy Tuple.first
        |> List.head
        |> Maybe.map Tuple.second


decodeLocationResult : Json.Decode.Decoder (Result LocationError { lat : Float, lon : Float, accuracy : Float })
decodeLocationResult =
    Json.Decode.oneOf
        [ Json.Decode.field "error" Json.Decode.string
            |> Json.Decode.map
                (\code ->
                    Err
                        (case code of
                            "permission_denied" ->
                                PermissionDenied

                            "timeout" ->
                                GeoTimeout

                            _ ->
                                PositionUnavailable
                        )
                )
        , Json.Decode.map3 (\lat lon acc -> Ok { lat = lat, lon = lon, accuracy = acc })
            (Json.Decode.field "lat" Json.Decode.float)
            (Json.Decode.field "lon" Json.Decode.float)
            (Json.Decode.field "accuracy" Json.Decode.float)
        ]


locationErrorToString : LocationError -> String
locationErrorToString err =
    case err of
        PermissionDenied ->
            "Location permission denied"

        PositionUnavailable ->
            "Position unavailable"

        GeoTimeout ->
            "Location request timed out"
