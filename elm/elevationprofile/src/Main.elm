port module Main exposing (storeState)

import Browser
import Browser.Navigation
import File exposing (File)
import File.Select
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Events
import Http
import Json.Decode
import Json.Encode
import String
import Svg
import Svg.Attributes
import Url exposing (Protocol(..))



-- MAIN


main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = \_ -> Ignore
        , onUrlChange = \_ -> Ignore
        }



-- MODEL


type alias Model =
    { track : LoadableResource TrackData
    , waypoints : List Waypoint
    , showOptions : Bool
    , gpxServerURLOverride : Maybe String
    }


type alias TrackData =
    List TrackPoint


type alias TrackPoint =
    { distance : Float
    , elevation : Float
    }


type alias Waypoint =
    { distance : Float
    }


type alias StoredState =
    { file : Maybe String
    , track : Maybe TrackData
    , waypoints : Maybe (List Waypoint)
    , gpxServerURL : Maybe String
    }


storedStateModel : StoredState -> Model
storedStateModel state =
    Model (loadableResourceFromMaybe state.track) (state.waypoints |> Maybe.withDefault []) True state.gpxServerURL


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState
        |> Maybe.map
            (Json.Decode.decodeValue storedStateDecoder
                -- TODO: handle error
                >> Result.withDefault (StoredState Nothing Nothing Nothing Nothing)
                >> storedStateModel
            )
        |> Maybe.withDefault (Model NotLoaded [] True Nothing)
    , Cmd.none
    )


type Msg
    = Ignore
    | ShowOptions Bool
    | OpenFileBrowser
    | FileUploaded File.File
    | ElevationProfileDataResponseReceived (Result String ElevationProfileDataResponse)
    | WaypointsTextChange String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ShowOptions show ->
            ( { model | showOptions = show }, Cmd.none )

        OpenFileBrowser ->
            ( model, File.Select.file [ "application/gpx+xml" ] FileUploaded )

        FileUploaded file ->
            updateModel { model | track = Loading }
                |> Tuple.mapSecond
                    (\cmd ->
                        Cmd.batch
                            [ cmd
                            , getElevationProfileDataResponse (Maybe.withDefault "https://gpx.fly.dev" model.gpxServerURLOverride) file
                            ]
                    )

        ElevationProfileDataResponseReceived resp ->
            case resp of
                Err errMsg ->
                    updateModel
                        { model | track = Error ("getting profile data from GPX: " ++ errMsg) }

                Ok data ->
                    updateModel
                        { model
                            | track = Loaded data.track
                            , waypoints = data.waypoints
                        }

        Ignore ->
            ( model, Cmd.none )

        WaypointsTextChange text ->
            updateModel
                { model
                    | waypoints = String.lines text |> List.filterMap String.toFloat |> List.map Waypoint
                }


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    let
        localStoredState =
            encodeSavedState model
    in
    ( model, storeState localStoredState )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    Browser.Document "Elevation profile"
        [ Html.div
            [ Html.Attributes.class "flex-container"
            , Html.Attributes.class "row"
            , Html.Attributes.class "page"
            , Html.Attributes.style "height" "100%"
            ]
            [ viewOptions model.showOptions model.waypoints
            , Html.div
                [ Html.Attributes.class "flex-container"
                , Html.Attributes.class "column"
                , Html.Attributes.class "wide"
                , Html.Attributes.style "height" "100%"
                , Html.Attributes.style "justify-content" "center"
                ]
                [ case model.track of
                    NotLoaded ->
                        Html.p [] [ Html.text "Load your profile!" ]

                    Loading ->
                        Html.p [] [ Html.text "Loading profile..." ]

                    Error err ->
                        viewErrorPanel <| ("There was an error creating your profile. Please fix any error and try again 😇\n\nError: " ++ String.left 1000 err ++ "...")

                    Loaded track ->
                        profile track model.waypoints
                ]
            ]
        ]


viewOptions : Bool -> List Waypoint -> Html Msg
viewOptions show waypoints =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "justify-content" "center"
        , Html.Attributes.style "overflow" "auto"
        , Html.Attributes.class "narrow"
        ]
        (if not show then
            [ Html.p
                [ Html.Events.onClick <| ShowOptions True
                , Html.Attributes.style "transform" "rotate(90deg)"
                , Html.Attributes.style "white-space" "nowrap"
                , Html.Attributes.style "width" "1em"
                ]
                [ Html.text "(show options)" ]
            ]

         else
            List.concat
                [ [ Html.div [ Html.Attributes.class "options" ] <|
                        [ Html.h2 [] [ Html.text "Options" ]
                        , Html.p [ Html.Events.onClick <| ShowOptions False ] [ Html.text "(hide)" ]
                        , Html.hr [] []
                        , Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.style "justify-content" "center"
                            , Html.Attributes.style "align-items" "center"
                            ]
                            [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "upload GPX" OpenFileBrowser
                            ]
                        , Html.div []
                            [ Html.textarea
                                [ Html.Attributes.placeholder "Newline delimited waypoint distances"
                                , Html.Attributes.value ((waypoints |> List.map (.distance >> String.fromFloat)) |> String.join "\n")
                                , Html.Events.onInput WaypointsTextChange
                                ]
                                []
                            ]
                        ]
                  ]
                ]
        )


viewErrorPanel : String -> Html Msg
viewErrorPanel error =
    Html.div [ Html.Attributes.class "error_panel" ] [ Html.text error ]


viewButtonWithAttributes : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButtonWithAttributes attrs text msg =
    Html.button
        ([ Html.Events.onClick msg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


profile : TrackData -> List Waypoint -> Html Msg
profile track waypoints =
    let
        -- TODO(ghanmer): combine these max folds to not iterate through twice
        maxElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.maximum <| List.map .elevation track

        minElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.minimum <| List.map .elevation track

        maxDistance =
            Maybe.withDefault 1 <| List.maximum <| List.map .distance track

        svgHeight =
            200

        svgWidth =
            500

        calc =
            xyCalculator
                { svgHeight = toFloat svgHeight
                , svgWidth = toFloat svgWidth
                , maxDistance = maxDistance
                , minElevation = minElevation
                , maxElevation = maxElevation
                }
    in
    Html.div
        [ Html.Attributes.class "TODO"
        ]
        [ Svg.svg
            [ Svg.Attributes.width "100%"
            , Svg.Attributes.height <| String.fromInt svgHeight

            --                          min-x min-y width height
            , Svg.Attributes.viewBox <| "0 0 " ++ String.fromInt svgWidth ++ " " ++ String.fromInt svgHeight
            ]
            (List.concat
                [ resolveElevationProfileSVGLine calc track
                , waypoints
                    |> List.map
                        (\waypoint ->
                            let
                                x =
                                    calc.x waypoint.distance

                                y =
                                    calc.y <| interpolateWaypointElevation track waypoint - 5
                            in
                            Svg.line
                                [ Svg.Attributes.x1 <| x
                                , Svg.Attributes.y1 <| String.fromInt svgHeight
                                , Svg.Attributes.x2 <| x
                                , Svg.Attributes.y2 <| y
                                , Svg.Attributes.stroke "grey"
                                , Svg.Attributes.strokeWidth "1"
                                ]
                                []
                        )
                , [ ( ( 0, 0 ), ( svgHeight, 0 ) )
                  , ( ( 0, 0 ), ( 0, svgWidth ) )
                  , ( ( svgHeight, svgWidth ), ( svgHeight, 0 ) )
                  , ( ( svgHeight, svgWidth ), ( 0, svgWidth ) )
                  ]
                    |> List.map
                        (\( ( y1, x1 ), ( y2, x2 ) ) ->
                            Svg.line
                                [ Svg.Attributes.x1 <| String.fromInt x1
                                , Svg.Attributes.y1 <| String.fromInt y1
                                , Svg.Attributes.x2 <| String.fromInt x2
                                , Svg.Attributes.y2 <| String.fromInt y2
                                , Svg.Attributes.stroke "grey"
                                , Svg.Attributes.strokeWidth "1"
                                ]
                                []
                        )
                ]
            )
        ]


interpolateWaypointElevation : TrackData -> Waypoint -> Float
interpolateWaypointElevation trackPoints waypoint =
    case trackPoints of
        [] ->
            0

        a :: others ->
            if a.distance >= waypoint.distance then
                a.elevation

            else
                case others of
                    [] ->
                        a.elevation

                    b :: _ ->
                        if b.distance >= waypoint.distance then
                            -- properly interpolate here
                            a.elevation

                        else
                            interpolateWaypointElevation others waypoint


resolveElevationProfileSVGLine : XYCalculator -> TrackData -> List (Svg.Svg msg)
resolveElevationProfileSVGLine calc profileData =
    profileData
        |> List.foldl
            (accumulatePoints calc)
            ( Nothing, [] )
        |> Tuple.second


type alias XYCalculator =
    { x : Float -> String
    , y : Float -> String
    }


xyCalculator :
    { svgWidth : Float
    , svgHeight : Float
    , maxDistance : Float
    , minElevation : Float
    , maxElevation : Float
    }
    -> XYCalculator
xyCalculator cfg =
    let
        elevationRange =
            cfg.maxElevation - cfg.minElevation

        normaliseElevation =
            \elevation -> (elevation - cfg.minElevation) / elevationRange

        svgWidthPerDistanceUnit =
            cfg.svgWidth / cfg.maxDistance
    in
    XYCalculator
        (\distance ->
            String.fromFloat (distance * svgWidthPerDistanceUnit)
        )
        (\elevation ->
            String.fromFloat (cfg.svgHeight - cfg.svgHeight * normaliseElevation elevation)
        )



-- accumulatePoints takes in a config to form an accumulator.
-- The accumulator will take a point and form a tuple of (maybePrevPoint, currentLines), where each line in currentLines
-- is a formed Svg.Svg msg.
-- The maybePrevPoint is a Maybe (String, String) because the number values have been converted in a prior iteration of
-- the accumulation loop.


accumulatePoints : XYCalculator -> (TrackPoint -> ( Maybe ( String, String ), List (Svg.Svg msg) ) -> ( Maybe ( String, String ), List (Svg.Svg msg) ))
accumulatePoints calc =
    \point ( maybePrevPoint, currLines ) ->
        let
            pointX =
                calc.x point.distance

            pointY =
                calc.y point.elevation
        in
        case maybePrevPoint of
            Nothing ->
                ( Just ( pointX, pointY ), [] )

            Just prev ->
                ( Just ( pointX, pointY )
                , Svg.line
                    [ Svg.Attributes.x1 <| Tuple.first prev
                    , Svg.Attributes.y1 <| Tuple.second prev
                    , Svg.Attributes.x2 <| pointX
                    , Svg.Attributes.y2 <| pointY
                    , Svg.Attributes.stroke "grey"
                    , Svg.Attributes.strokeWidth "1"
                    ]
                    []
                    :: currLines
                )



-- GPX API


type alias ElevationProfileDataResponse =
    { track : TrackData
    , waypoints : List Waypoint
    }


decodeElevationProfileDataResponse : Json.Decode.Decoder ElevationProfileDataResponse
decodeElevationProfileDataResponse =
    Json.Decode.map2 ElevationProfileDataResponse
        (Json.Decode.field "track" decodeTrack)
        (Json.Decode.field "waypoints" decodeWaypoints)


getElevationProfileDataResponse : String -> File.File -> Cmd Msg
getElevationProfileDataResponse url file =
    Http.post
        { url = url
        , body = Http.fileBody file
        , expect =
            Http.expectJson
                (Result.mapError httpErrorString >> ElevationProfileDataResponseReceived)
                decodeElevationProfileDataResponse
        }



-- ENCODE/DECODE MODEL


encodeTrack : TrackData -> Json.Encode.Value
encodeTrack =
    Json.Encode.list
        (\point ->
            Json.Encode.object
                [ ( "dist", Json.Encode.float point.distance )
                , ( "ele", Json.Encode.float point.elevation )
                ]
        )


decodeTrack : Json.Decode.Decoder TrackData
decodeTrack =
    Json.Decode.list
        (Json.Decode.map2 TrackPoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "ele" Json.Decode.float)
        )


encodeWaypoints : List Waypoint -> Json.Encode.Value
encodeWaypoints =
    Json.Encode.list
        (\waypoint -> Json.Encode.object [ ( "dist", Json.Encode.float waypoint.distance ) ])


decodeWaypoints : Json.Decode.Decoder (List Waypoint)
decodeWaypoints =
    Json.Decode.list
        (Json.Decode.map Waypoint
            (Json.Decode.field "dist" Json.Decode.float)
         --(Json.Decode.field "ele" Json.Decode.float)
        )



-- STATE


encodeSavedState : Model -> String
encodeSavedState model =
    Json.Encode.object
        (List.filterMap
            identity
            [ case model.track of
                Loaded data ->
                    Just ( "track", encodeTrack data )

                _ ->
                    Nothing
            , Just ( "waypoints", encodeWaypoints model.waypoints )
            , Maybe.map (\url -> ( "gpxServerURL", Json.Encode.string url )) model.gpxServerURLOverride
            ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : Json.Decode.Decoder StoredState
storedStateDecoder =
    Json.Decode.map4 StoredState
        (Json.Decode.maybe (Json.Decode.field "file" Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field "track" decodeTrack))
        (Json.Decode.maybe (Json.Decode.field "waypoints" decodeWaypoints))
        (Json.Decode.maybe (Json.Decode.field "gpxServerURL" Json.Decode.string))


port storeState : String -> Cmd msg



-- PKG


type LoadableResource a
    = NotLoaded
    | Loading
    | Error String
    | Loaded a


loadableResourceFromMaybe : Maybe a -> LoadableResource a
loadableResourceFromMaybe =
    Maybe.map Loaded >> Maybe.withDefault NotLoaded


httpErrorString : Http.Error -> String
httpErrorString err =
    case err of
        Http.BadUrl msg ->
            "bad url: " ++ msg

        Http.Timeout ->
            "timeout"

        Http.NetworkError ->
            "network error"

        -- TODO(glynternet): can we capture the error message from the body?
        Http.BadStatus code ->
            "bad status: " ++ String.fromInt code

        Http.BadBody msg ->
            "bad body: " ++ msg
