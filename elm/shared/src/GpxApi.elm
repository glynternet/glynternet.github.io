module GpxApi exposing
    ( SplitResult
    , Track
    , TrackPoint
    , Waypoint
    , decodeElevationProfileDataResponse
    , decodeResult
    , decodeSplitResult
    , decodeTrack
    , decodeTrackpoints
    , decodeWaypoints
    , encodeTrack
    )

import Json.Decode
import Json.Encode


type alias Track =
    { trackpoints : List TrackPoint
    , waypoints : List Waypoint
    , gainLoss : ( Float, Float )
    }


type alias TrackPoint =
    { distance : Float
    , elevation : Float
    , lat : Float
    , lon : Float
    , gain : Float
    , loss : Float
    }


type alias Waypoint =
    { distance : Float
    , name : String
    , categories : List String
    , gain : Float
    , loss : Float
    }



--DECODE


decodeElevationProfileDataResponse : Json.Decode.Decoder (List Track)
decodeElevationProfileDataResponse =
    Json.Decode.list decodeTrack


decodeTrack : Json.Decode.Decoder Track
decodeTrack =
    Json.Decode.map3 Track
        (Json.Decode.field "track" decodeTrackpoints)
        (Json.Decode.field "waypoints" (Json.Decode.oneOf [ decodeWaypoints, Json.Decode.null [] ]))
        (Json.Decode.map2 Tuple.pair
            (Json.Decode.field "gain" Json.Decode.float)
            (Json.Decode.field "loss" Json.Decode.float)
        )


decodeTrackpoints : Json.Decode.Decoder (List TrackPoint)
decodeTrackpoints =
    Json.Decode.list
        (Json.Decode.map6 TrackPoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "ele" Json.Decode.float)
            (Json.Decode.field "lat" Json.Decode.float)
            (Json.Decode.field "lon" Json.Decode.float)
            (Json.Decode.field "gain" Json.Decode.float)
            (Json.Decode.field "loss" Json.Decode.float)
        )


decodeWaypoints : Json.Decode.Decoder (List Waypoint)
decodeWaypoints =
    Json.Decode.list
        (Json.Decode.map5 Waypoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "name" Json.Decode.string)
            (Json.Decode.field "categories" <| jsonDecodeNullableList Json.Decode.string)
            (Json.Decode.oneOf [ Json.Decode.field "gain" Json.Decode.float, Json.Decode.succeed 0 ])
            (Json.Decode.oneOf [ Json.Decode.field "loss" Json.Decode.float, Json.Decode.succeed 0 ])
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



--ENCODE


encodeTrack : Track -> Json.Encode.Value
encodeTrack track =
    Json.Encode.object
        [ ( "track", encodeTrackpoints track.trackpoints )
        , ( "waypoints", encodeWaypoints track.waypoints )
        , ( "gain", Json.Encode.float (Tuple.first track.gainLoss) )
        , ( "loss", Json.Encode.float (Tuple.second track.gainLoss) )
        ]


encodeTrackpoints : List TrackPoint -> Json.Encode.Value
encodeTrackpoints =
    Json.Encode.list
        (\point ->
            Json.Encode.object
                [ ( "dist", Json.Encode.float point.distance )
                , ( "ele", Json.Encode.float point.elevation )
                , ( "lat", Json.Encode.float point.lat )
                , ( "lon", Json.Encode.float point.lon )
                , ( "gain", Json.Encode.float point.gain )
                , ( "loss", Json.Encode.float point.loss )
                ]
        )


encodeWaypoints : List Waypoint -> Json.Encode.Value
encodeWaypoints =
    Json.Encode.list
        (\waypoint ->
            Json.Encode.object
                [ ( "dist", Json.Encode.float waypoint.distance )
                , ( "name", Json.Encode.string waypoint.name )
                , ( "categories", Json.Encode.list Json.Encode.string waypoint.categories )
                , ( "gain", Json.Encode.float waypoint.gain )
                , ( "loss", Json.Encode.float waypoint.loss )
                ]
        )



-- SPLIT RESULT


type alias SplitResult =
    { segments : List Track
    , boundaries : List ( Float, Float )
    }


decodeSplitResult : Json.Decode.Decoder SplitResult
decodeSplitResult =
    Json.Decode.map2 SplitResult
        (Json.Decode.field "segments" (Json.Decode.list decodeTrack))
        (Json.Decode.field "boundaries" decodeBoundaries)


decodeBoundaries : Json.Decode.Decoder (List ( Float, Float ))
decodeBoundaries =
    Json.Decode.list
        (Json.Decode.map2 Tuple.pair
            (Json.Decode.index 0 Json.Decode.float)
            (Json.Decode.index 1 Json.Decode.float)
        )
