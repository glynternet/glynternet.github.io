module GpxApi exposing (Track, TrackPoint, Waypoint, decodeElevationProfileDataResponse, decodeResult, decodeTrackpoints, decodeWaypoints)

import Json.Decode


type alias Track =
    { trackpoints : List TrackPoint
    , waypoints : List Waypoint
    }


type alias TrackPoint =
    { distance : Float
    , elevation : Float
    , lat : Float
    , lon : Float
    }


type alias Waypoint =
    { distance : Float
    , name : String
    , categories : List String
    }


decodeElevationProfileDataResponse : Json.Decode.Decoder (List Track)
decodeElevationProfileDataResponse =
    Json.Decode.list
        (Json.Decode.map2 Track
            (Json.Decode.field "track" decodeTrackpoints)
            (Json.Decode.oneOf [ Json.Decode.field "waypoints" decodeWaypoints, Json.Decode.null [] ])
        )


decodeTrackpoints : Json.Decode.Decoder (List TrackPoint)
decodeTrackpoints =
    Json.Decode.list
        (Json.Decode.map4 TrackPoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "ele" Json.Decode.float)
            (Json.Decode.field "lat" Json.Decode.float)
            (Json.Decode.field "lon" Json.Decode.float)
        )


decodeWaypoints : Json.Decode.Decoder (List Waypoint)
decodeWaypoints =
    Json.Decode.list
        (Json.Decode.map3 Waypoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "name" Json.Decode.string)
            (Json.Decode.field "categories" <| jsonDecodeNullableList Json.Decode.string)
        )


decodeResult : Json.Decode.Decoder a -> Json.Decode.Decoder (Result String a)
decodeResult decoder =
    Json.Decode.oneOf
        [ Json.Decode.field "error" Json.Decode.string |> Json.Decode.map Result.Err
        , decoder |> Json.Decode.map Result.Ok
        ]


jsonDecodeNullableList : Json.Decode.Decoder a -> Json.Decode.Decoder (List a)
jsonDecodeNullableList elementDecoder =
    Json.Decode.oneOf [ Json.Decode.list elementDecoder, Json.Decode.null [] ]
