module PositionalTracks exposing
    ( PositionalTracks
    , decoder
    , encode
    , fromList
    , navigateNext
    , navigatePrevious
    , updateCurrent
    )

import GpxApi
import Json.Decode
import Json.Encode


type alias PositionalTracks =
    { prev : List GpxApi.Track
    , current : GpxApi.Track
    , next : List GpxApi.Track
    }


fromList : List GpxApi.Track -> Maybe PositionalTracks
fromList tracks =
    case tracks of
        first :: rest ->
            Just (PositionalTracks [] first rest)

        [] ->
            Nothing


navigatePrevious : PositionalTracks -> PositionalTracks
navigatePrevious tracks =
    case tracks.prev of
        [] ->
            tracks

        first :: rest ->
            PositionalTracks rest first (tracks.current :: tracks.next)


navigateNext : PositionalTracks -> PositionalTracks
navigateNext tracks =
    case tracks.next of
        [] ->
            tracks

        first :: rest ->
            PositionalTracks (tracks.current :: tracks.prev) first rest


updateCurrent : (GpxApi.Track -> GpxApi.Track) -> PositionalTracks -> PositionalTracks
updateCurrent updateTrack tracks =
    PositionalTracks tracks.prev (updateTrack tracks.current) tracks.next



-- ENCODE/DECODE


encode : PositionalTracks -> Json.Encode.Value
encode tracks =
    Json.Encode.object
        [ ( "previous", Json.Encode.list encodeTrack tracks.prev )
        , ( "current", encodeTrack tracks.current )
        , ( "next", Json.Encode.list encodeTrack tracks.next )
        ]


decoder : Json.Decode.Decoder PositionalTracks
decoder =
    Json.Decode.map3 PositionalTracks
        (Json.Decode.field "previous" (Json.Decode.list decodeTrack))
        (Json.Decode.field "current" decodeTrack)
        (Json.Decode.field "next" (Json.Decode.list decodeTrack))


encodeTrack : GpxApi.Track -> Json.Encode.Value
encodeTrack track =
    Json.Encode.object
        [ ( "trackpoints", encodeTrackpoints track.trackpoints )
        , ( "waypoints", encodeWaypoints track.waypoints )
        ]


decodeTrack : Json.Decode.Decoder GpxApi.Track
decodeTrack =
    Json.Decode.map2 GpxApi.Track
        (Json.Decode.field "trackpoints" GpxApi.decodeTrackpoints)
        (Json.Decode.field "waypoints" GpxApi.decodeWaypoints)


encodeTrackpoints : List GpxApi.TrackPoint -> Json.Encode.Value
encodeTrackpoints =
    Json.Encode.list
        (\point ->
            Json.Encode.object
                [ ( "dist", Json.Encode.float point.distance )
                , ( "ele", Json.Encode.float point.elevation )
                , ( "lat", Json.Encode.float point.lat )
                , ( "lon", Json.Encode.float point.lon )
                ]
        )


encodeWaypoints : List GpxApi.Waypoint -> Json.Encode.Value
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
