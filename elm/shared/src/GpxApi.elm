module GpxApi exposing (Track, TrackPoint, Waypoint, decodeTrackpoints, decodeWaypoints, getElevationProfileDataResponse, httpErrorString)

import File exposing (File)
import Http
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
    }


getElevationProfileDataResponse : (Result String (List Track) -> msg) -> String -> File -> Cmd msg
getElevationProfileDataResponse toMsg url file =
    Http.post
        { url = url
        , body = Http.fileBody file
        , expect =
            Http.expectJson
                (Result.mapError httpErrorString >> toMsg)
                decodeElevationProfileDataResponse
        }


decodeElevationProfileDataResponse : Json.Decode.Decoder (List Track)
decodeElevationProfileDataResponse =
    Json.Decode.list
        (Json.Decode.map2 Track
            (Json.Decode.field "track" decodeTrackpoints)
            (Json.Decode.maybe (Json.Decode.field "waypoints" decodeWaypoints)
                |> Json.Decode.map (Maybe.withDefault [])
            )
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
        (Json.Decode.map2 Waypoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "name" Json.Decode.string)
        )


httpErrorString : Http.Error -> String
httpErrorString err =
    case err of
        Http.BadUrl msg ->
            "bad url: " ++ msg

        Http.Timeout ->
            "timeout"

        Http.NetworkError ->
            "network error"

        Http.BadStatus code ->
            "bad status: " ++ String.fromInt code

        Http.BadBody msg ->
            "bad body: " ++ msg
