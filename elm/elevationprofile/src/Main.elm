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
import List.Extra
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
    , fontSize : Float
    , trackHeight : Int
    , trackThickness : Float
    , waypointStrokeColor : String
    }


type alias TrackData =
    List TrackPoint


type alias TrackPoint =
    { distance : Float
    , elevation : Float
    }


type alias Waypoint =
    { distance : Float
    , name : String
    }


type alias StoredState =
    { track : Maybe TrackData
    , waypoints : Maybe (List Waypoint)
    , gpxServerURL : Maybe String
    , fontSize : Maybe Float
    , trackHeight : Maybe Int
    , trackThickness : Maybe Float
    , waypointStrokeColor : Maybe String
    }


storedStateModel : StoredState -> Model
storedStateModel state =
    Model (loadableResourceFromMaybe state.track)
        (state.waypoints |> Maybe.withDefault [])
        True
        state.gpxServerURL
        (Maybe.withDefault 15 state.fontSize)
        (Maybe.withDefault 200 state.trackHeight)
        (Maybe.withDefault 1 state.trackThickness)
        (Maybe.withDefault "lightgray" state.waypointStrokeColor)


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState
        |> Maybe.map
            (Json.Decode.decodeValue storedStateDecoder
                -- TODO: handle error
                >> Result.withDefault (StoredState Nothing Nothing Nothing Nothing Nothing Nothing Nothing)
                >> storedStateModel
            )
        |> Maybe.withDefault (Model NotLoaded [] True Nothing 15 200 1 "lightgray")
    , Cmd.none
    )


type Msg
    = Ignore
    | ShowOptions Bool
    | OpenFileBrowser
    | FileUploaded File.File
    | ElevationProfileDataResponseReceived (Result String ElevationProfileDataResponse)
    | WaypointDistanceChange Int Float
    | WaypointNameChange Int String
    | DeleteWaypoint Int
    | UpdateFontSize Float
    | UpdateTrackHeight Int
    | UpdateTrackThickness Float
    | WaypointStrokeColourChange String


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

        WaypointNameChange i name ->
            List.Extra.getAt i model.waypoints
                |> Maybe.map
                    (\waypoint -> updateModel { model | waypoints = List.Extra.setAt i { waypoint | name = name } model.waypoints })
                |> Maybe.withDefault ( model, Cmd.none )

        WaypointDistanceChange i dist ->
            List.Extra.getAt i model.waypoints
                |> Maybe.map
                    (\waypoint -> updateModel { model | waypoints = List.Extra.setAt i { waypoint | distance = dist } model.waypoints })
                |> Maybe.withDefault ( model, Cmd.none )

        DeleteWaypoint i ->
            updateModel { model | waypoints = List.Extra.removeAt i model.waypoints }

        UpdateFontSize size ->
            updateModel { model | fontSize = size }

        UpdateTrackHeight height ->
            updateModel { model | trackHeight = height }

        UpdateTrackThickness thickness ->
            updateModel { model | trackThickness = thickness }

        WaypointStrokeColourChange colour ->
            updateModel { model | waypointStrokeColor = colour }


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    ( model, storeState (storedStateFromModel model |> encodeSavedState) )



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
            [ viewOptions model.showOptions model.fontSize model.trackHeight model.trackThickness model.waypointStrokeColor
            , Html.div
                [ Html.Attributes.class "flex-container"
                , Html.Attributes.class "column"
                , Html.Attributes.class "wide"
                , Html.Attributes.style "height" "100%"
                , Html.Attributes.style "overflow" "auto"
                ]
                (case model.track of
                    NotLoaded ->
                        [ Html.p [] [ Html.text "Load your profile!" ] ]

                    Loading ->
                        [ Html.p [] [ Html.text "Loading profile..." ] ]

                    Error err ->
                        [ viewErrorPanel <| ("There was an error creating your profile. Please fix any error and try again 😇\n\nError: " ++ String.left 1000 err ++ "...") ]

                    Loaded track ->
                        let
                            maxDistance =
                                Maybe.withDefault 1 <| List.maximum <| List.map .distance track
                        in
                        [ profile track model.waypoints maxDistance model.fontSize model.trackHeight model.trackThickness model.waypointStrokeColor
                        , Html.div []
                            (model.waypoints
                                |> List.indexedMap
                                    (\i waypoint ->
                                        Html.div []
                                            [ Html.input
                                                [ Html.Attributes.type_ "number"
                                                , Html.Attributes.min "0"
                                                , maxDistance |> (String.fromFloat >> Html.Attributes.max)
                                                , Html.Attributes.value <| String.fromFloat waypoint.distance

                                                -- handle toFloat error
                                                , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1000 >> WaypointDistanceChange i)
                                                ]
                                                []
                                            , Html.textarea
                                                [ Html.Attributes.placeholder "Waypoint name..."
                                                , Html.Attributes.value waypoint.name
                                                , Html.Events.onInput <| WaypointNameChange i
                                                ]
                                                []
                                            , viewButtonWithAttributes [] "X" (DeleteWaypoint i)
                                            ]
                                    )
                            )
                        ]
                )
            ]
        ]


viewOptions : Bool -> Float -> Int -> Float -> String -> Html Msg
viewOptions show fontSize trackHeight trackThickness waypointStrokeColor =
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
                            , optionGroup "Font size"
                                [ Html.input
                                    [ Html.Attributes.type_ "range"
                                    , Html.Attributes.min "1"
                                    , Html.Attributes.max "50"
                                    , Html.Attributes.value <| String.fromFloat fontSize
                                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 15 >> UpdateFontSize)
                                    ]
                                    []
                                ]
                            , optionGroup "Track height"
                                [ Html.input
                                    [ Html.Attributes.type_ "range"
                                    , Html.Attributes.min "1"
                                    , Html.Attributes.max "400"
                                    , Html.Attributes.value <| String.fromInt trackHeight
                                    , Html.Events.onInput (String.toInt >> Maybe.withDefault 200 >> UpdateTrackHeight)
                                    ]
                                    []
                                ]
                            , optionGroup "Track thickness"
                                [ Html.input
                                    [ Html.Attributes.type_ "range"
                                    , Html.Attributes.min "0.1"
                                    , Html.Attributes.max "10"
                                    , Html.Attributes.step "0.1"
                                    , Html.Attributes.value <| String.fromFloat trackThickness
                                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1 >> UpdateTrackThickness)
                                    ]
                                    []
                                ]
                            , optionGroup "Waypoint stroke colour"
                                [ Html.textarea
                                    [ Html.Attributes.placeholder "Waypoint stroke colour..."
                                    , Html.Attributes.value waypointStrokeColor
                                    , Html.Events.onInput <| WaypointStrokeColourChange
                                    ]
                                    []
                                ]
                            ]
                        ]
                  ]
                ]
        )


viewErrorPanel : String -> Html Msg
viewErrorPanel error =
    Html.div [ Html.Attributes.class "error_panel" ] [ Html.text error ]


viewButtonWithAttributes : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButtonWithAttributes attrs text onClickMsg =
    Html.button
        ([ Html.Events.onClick onClickMsg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


optionGroup : String -> List (Html Msg) -> Html Msg
optionGroup title elements =
    Html.div [ Html.Attributes.class "flex-container", Html.Attributes.class "column" ]
        (Html.legend [] [ Html.text title ] :: elements)


profile : TrackData -> List Waypoint -> Float -> Float -> Int -> Float -> String -> Html Msg
profile track waypoints maxDistance fontSize trackHeight trackThickness waypointStrokeColor =
    let
        -- TODO(ghanmer): combine these max folds to not iterate through twice
        maxElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.maximum <| List.map .elevation track

        minElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.minimum <| List.map .elevation track

        waypointTextHeight =
            100

        svgHeight =
            trackHeight + waypointTextHeight

        svgWidth =
            500

        calc =
            xyCalculator
                { svgHeight = toFloat trackHeight
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
            [ -- add 5 onto each side to ensure nothing cutoff when items are placed right at edges
              --                          min-x min-y width height
              Svg.Attributes.viewBox <| "-5 -5 " ++ String.fromInt (svgWidth + 10) ++ " " ++ (String.fromInt <| svgHeight + 10)
            ]
            [ -- waypoints
              Svg.g []
                (let
                    svgBottom =
                        String.fromInt svgHeight

                    paddedWaypointTextY =
                        String.fromInt <| trackHeight + 5
                 in
                 waypoints
                    |> List.concatMap
                        (\waypoint ->
                            let
                                x =
                                    calc.x waypoint.distance

                                y =
                                    calc.y <| interpolateWaypointElevation track waypoint - 5
                            in
                            [ Svg.line
                                [ Svg.Attributes.x1 <| x
                                , Svg.Attributes.y1 <| svgBottom
                                , Svg.Attributes.x2 <| x
                                , Svg.Attributes.y2 <| y
                                , Svg.Attributes.stroke waypointStrokeColor
                                , Svg.Attributes.strokeWidth "1"
                                ]
                                []
                            , Svg.text_
                                [ Svg.Attributes.fontSize <| String.fromFloat fontSize
                                , Svg.Attributes.dominantBaseline "text-top"
                                , Svg.Attributes.transform <| "translate(" ++ x ++ ", " ++ paddedWaypointTextY ++ ") rotate(90)"
                                ]
                                [ Svg.text waypoint.name ]
                            ]
                        )
                )
            , -- track line
              Svg.g [] <| resolveElevationProfileSVGLine calc track (String.fromFloat trackThickness)
            , -- track border
              Svg.g []
                ([ ( ( 0, 0 ), ( trackHeight, 0 ) )
                 , ( ( 0, 0 ), ( 0, svgWidth ) )
                 , ( ( trackHeight, svgWidth ), ( trackHeight, 0 ) )
                 , ( ( trackHeight, svgWidth ), ( 0, svgWidth ) )
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
                )
            ]
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


resolveElevationProfileSVGLine : XYCalculator -> TrackData -> String -> List (Svg.Svg msg)
resolveElevationProfileSVGLine calc profileData trackThicknessAttrValue =
    profileData
        |> List.foldl
            (accumulatePoints calc trackThicknessAttrValue)
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


accumulatePoints : XYCalculator -> String -> (TrackPoint -> ( Maybe ( String, String ), List (Svg.Svg msg) ) -> ( Maybe ( String, String ), List (Svg.Svg msg) ))
accumulatePoints calc trackThicknessAttrValue =
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
                    , Svg.Attributes.strokeWidth trackThicknessAttrValue
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
        (Json.Decode.maybe (Json.Decode.field "waypoints" decodeWaypoints)
            |> Json.Decode.map (Maybe.withDefault [])
        )


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
        (\waypoint ->
            Json.Encode.object
                [ ( "dist", Json.Encode.float waypoint.distance )
                , ( "name", Json.Encode.string waypoint.name )
                ]
        )


decodeWaypoints : Json.Decode.Decoder (List Waypoint)
decodeWaypoints =
    Json.Decode.list
        (Json.Decode.map2 Waypoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "name" Json.Decode.string)
        )



-- STATE


storedStateFromModel : Model -> StoredState
storedStateFromModel model =
    StoredState
        (maybeFromloadableResource model.track)
        (if List.length model.waypoints > 0 then
            Just model.waypoints

         else
            Nothing
        )
        model.gpxServerURLOverride
        (Just model.fontSize)
        (Just model.trackHeight)
        (Just model.trackThickness)
        (Just model.waypointStrokeColor)


encodeSavedState : StoredState -> String
encodeSavedState state =
    Json.Encode.object
        (List.filterMap
            identity
            [ state.waypoints |> Maybe.map (\waypoints -> ( "waypoints", encodeWaypoints waypoints ))
            , state.gpxServerURL |> Maybe.map (\url -> ( "gpxServerURL", Json.Encode.string url ))
            , state.fontSize |> Maybe.map (\size -> ( "fontSize", Json.Encode.float size ))
            , state.trackHeight |> Maybe.map (\height -> ( "trackHeight", Json.Encode.int height ))
            , state.trackThickness |> Maybe.map (\thickness -> ( "trackThickness", Json.Encode.float thickness ))
            , state.waypointStrokeColor |> Maybe.map (\colour -> ( "waypointStrokeColor", Json.Encode.string colour ))
            , state.track |> Maybe.map (\track -> ( "track", encodeTrack track ))
            ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : Json.Decode.Decoder StoredState
storedStateDecoder =
    Json.Decode.map7 StoredState
        (Json.Decode.maybe (Json.Decode.field "track" decodeTrack))
        (Json.Decode.maybe (Json.Decode.field "waypoints" decodeWaypoints))
        (Json.Decode.maybe (Json.Decode.field "gpxServerURL" Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field "fontSize" Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "trackHeight" Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field "trackThickness" Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "waypointStrokeColor" Json.Decode.string))


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


maybeFromloadableResource : LoadableResource a -> Maybe a
maybeFromloadableResource resource =
    case resource of
        Loaded a ->
            Just a

        _ ->
            Nothing


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
