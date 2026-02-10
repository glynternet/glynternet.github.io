port module Main exposing (main)

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
import Time
import Url exposing (Protocol(..))



-- MAIN


main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = \_ -> Ignore
        , onUrlChange = \_ -> Ignore
        }



subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ receiveLocation LocationReceived
        , if model.trackingEnabled then
            Time.every (toFloat model.trackingIntervalSec * 1000) Tick

          else
            Sub.none
        ]



-- MODEL


type alias Model =
    { tracks : LoadableResource Tracks
    , showOptions : Bool
    , showWaypointEditor : Bool
    , gpxServerURLOverride : Maybe String
    , fontSize : Float
    , trackHeight : Int
    , trackThickness : Float
    , waypointStrokeColor : String
    , showIntensity : Bool
    , intensityTau : Float
    , location : Maybe LocationState
    , locationError : Maybe LocationError
    , trackingEnabled : Bool
    , trackingIntervalSec : Int
    }


type alias Tracks =
    { prev : List Track
    , current : Track
    , next : List Track
    }


tracksUpdateCurrent : (Track -> Track) -> Tracks -> Tracks
tracksUpdateCurrent updateTrack tracks =
    Tracks tracks.prev (updateTrack tracks.current) tracks.next


type alias Track =
    { trackpoints : List TrackPoint
    , waypoints : List Waypoint
    }


trackWithWaypoints : Track -> List Waypoint -> Track
trackWithWaypoints track waypoints =
    { track | waypoints = waypoints }


trackUpdateWaypoint : Track -> Int -> (Waypoint -> Waypoint) -> Track
trackUpdateWaypoint track i updateWaypoint =
    trackWithWaypoints track <| List.Extra.updateAt i updateWaypoint track.waypoints


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


type alias LatLon =
    { lat : Float
    , lon : Float
    }


type alias LocationState =
    { position : LatLon
    , accuracy : Float
    , matchedDistance : Float
    }


type LocationError
    = PermissionDenied
    | PositionUnavailable
    | GeoTimeout


type alias StoredState =
    { tracks : Maybe Tracks
    , gpxServerURL : Maybe String
    , fontSize : Maybe Float
    , trackHeight : Maybe Int
    , trackThickness : Maybe Float
    , waypointStrokeColor : Maybe String
    , trackingIntervalSec : Maybe Int
    , showIntensity : Maybe Bool
    , intensityTau : Maybe Float
    }


storedStateModel : StoredState -> Model
storedStateModel state =
    { tracks = loadableResourceFromMaybe state.tracks
    , showOptions = True
    , showWaypointEditor = False
    , gpxServerURLOverride = state.gpxServerURL
    , fontSize = Maybe.withDefault 15 state.fontSize
    , trackHeight = Maybe.withDefault 200 state.trackHeight
    , trackThickness = Maybe.withDefault 1 state.trackThickness
    , waypointStrokeColor = Maybe.withDefault "lightgray" state.waypointStrokeColor
    , showIntensity = Maybe.withDefault False state.showIntensity
    , intensityTau = Maybe.withDefault 500 state.intensityTau
    , location = Nothing
    , locationError = Nothing
    , trackingEnabled = False
    , trackingIntervalSec = Maybe.withDefault 60 state.trackingIntervalSec
    }


defaultStoredState : StoredState
defaultStoredState =
    StoredState Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState
        |> Maybe.map
            (Json.Decode.decodeValue storedStateDecoder
                -- TODO: handle error
                >> Result.withDefault defaultStoredState
                >> storedStateModel
            )
        |> Maybe.withDefault (storedStateModel defaultStoredState)
    , Cmd.none
    )


type Msg
    = Ignore
    | ShowOptions Bool
    | ShowWaypointEditor Bool
    | OpenFileBrowser
    | FileUploaded File.File
    | ElevationProfileDataResponseReceived (Result String ElevationProfileDataResponse)
    | NavigateToPrevious
    | NavigateToNext
    | WaypointDistanceChange Int Float
    | WaypointNameChange Int String
    | DeleteWaypoint Int
    | UpdateFontSize Float
    | UpdateTrackHeight Int
    | UpdateTrackThickness Float
    | WaypointStrokeColourChange String
    | LocationReceived Json.Decode.Value
    | RequestLocation
    | ToggleTracking
    | SetTrackingInterval Int
    | ShowIntensity Bool
    | UpdateIntensityTau Float
    | Tick Time.Posix


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ShowOptions show ->
            ( { model | showOptions = show }, Cmd.none )

        ShowWaypointEditor show ->
            updateModel { model | showWaypointEditor = show }

        OpenFileBrowser ->
            ( model, File.Select.file [ "application/gpx+xml" ] FileUploaded )

        FileUploaded file ->
            updateModel { model | tracks = Loading }
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
                        { model | tracks = Error ("getting profile data from GPX: " ++ errMsg) }

                Ok tracks ->
                    updateModel
                        { model
                            | tracks =
                                case tracks of
                                    [] ->
                                        Error "No tracks available in uploaded GPX 😢"

                                    first :: rest ->
                                        Loaded <| Tracks [] first rest
                        }

        Ignore ->
            ( model, Cmd.none )

        NavigateToPrevious ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model
                            | tracks =
                                Loaded <|
                                    case tracks.prev of
                                        [] ->
                                            tracks

                                        first :: rest ->
                                            Tracks rest first (tracks.current :: tracks.next)
                        }

                _ ->
                    ( model, Cmd.none )

        NavigateToNext ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model
                            | tracks =
                                Loaded <|
                                    case tracks.next of
                                        [] ->
                                            tracks

                                        first :: rest ->
                                            Tracks (tracks.current :: tracks.prev) first rest
                        }

                _ ->
                    ( model, Cmd.none )

        WaypointNameChange i name ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model
                            | tracks =
                                Loaded <|
                                    Tracks
                                        tracks.prev
                                        (trackUpdateWaypoint tracks.current i (\w -> { w | name = name }))
                                        tracks.next
                        }

                _ ->
                    ( model, Cmd.none )

        WaypointDistanceChange i dist ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model
                            | tracks =
                                Loaded <|
                                    Tracks
                                        tracks.prev
                                        (trackUpdateWaypoint tracks.current i (\w -> { w | distance = dist }))
                                        tracks.next
                        }

                _ ->
                    ( model, Cmd.none )

        DeleteWaypoint i ->
            case model.tracks of
                Loaded tracks ->
                    updateModel { model | tracks = Loaded <| tracksUpdateCurrent (\current -> trackWithWaypoints current (List.Extra.removeAt i current.waypoints)) tracks }

                _ ->
                    ( model, Cmd.none )

        UpdateFontSize size ->
            updateModel { model | fontSize = size }

        UpdateTrackHeight height ->
            updateModel { model | trackHeight = height }

        UpdateTrackThickness thickness ->
            updateModel { model | trackThickness = thickness }

        WaypointStrokeColourChange colour ->
            updateModel { model | waypointStrokeColor = colour }

        ShowIntensity show ->
            updateModel { model | showIntensity = show }

        UpdateIntensityTau tau ->
            updateModel { model | intensityTau = tau }

        RequestLocation ->
            ( model, requestLocation () )

        ToggleTracking ->
            let
                nowEnabled =
                    not model.trackingEnabled
            in
            if nowEnabled then
                updateModel { model | trackingEnabled = True }
                    |> Tuple.mapSecond (\cmd -> Cmd.batch [ cmd, requestLocation () ])

            else
                updateModel { model | trackingEnabled = False }

        SetTrackingInterval interval ->
            updateModel { model | trackingIntervalSec = interval }

        Tick _ ->
            ( model, requestLocation () )

        LocationReceived value ->
            case Json.Decode.decodeValue decodeLocationResult value of
                Ok (Ok pos) ->
                    case model.tracks of
                        Loaded tracks ->
                            let
                                gpsPos =
                                    LatLon pos.lat pos.lon

                                matchedDist =
                                    findNearestTrackPoint gpsPos tracks.current.trackpoints
                                        |> Maybe.map .distance
                                        |> Maybe.withDefault 0
                            in
                            ( { model
                                | location = Just (LocationState gpsPos pos.accuracy matchedDist)
                                , locationError = Nothing
                              }
                            , Cmd.none
                            )

                        _ ->
                            ( { model | locationError = Nothing }, Cmd.none )

                Ok (Err locErr) ->
                    ( { model | locationError = Just locErr }, Cmd.none )

                -- JSON decode failure; treat as unavailable
                Err _ ->
                    ( { model | locationError = Just PositionUnavailable }, Cmd.none )


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
            [ viewOptions
                { show = model.showOptions
                , showWaypointEditor = model.showWaypointEditor
                , tracks = maybeFromloadableResource model.tracks
                , fontSize = model.fontSize
                , trackHeight = model.trackHeight
                , trackThickness = model.trackThickness
                , waypointStrokeColor = model.waypointStrokeColor
                , location = model.location
                , locationError = model.locationError
                , trackingEnabled = model.trackingEnabled
                , trackingIntervalSec = model.trackingIntervalSec
                , showIntensity = model.showIntensity
                , intensityTau = model.intensityTau
                }
            , Html.div
                [ Html.Attributes.class "flex-container"
                , Html.Attributes.class "column"
                , Html.Attributes.class "wide"
                , Html.Attributes.style "height" "100%"
                , Html.Attributes.style "overflow" "auto"
                ]
                (case model.tracks of
                    NotLoaded ->
                        [ Html.p [] [ Html.text "Load your profile!" ] ]

                    Loading ->
                        [ Html.p [] [ Html.text "Loading profile..." ] ]

                    Error err ->
                        [ viewErrorPanel <| ("There was an error creating your profile. Please fix any error and try again 😇\n\nError: " ++ String.left 1000 err ++ "...") ]

                    Loaded tracks ->
                        let
                            maxDistance =
                                Maybe.withDefault 1 <| List.maximum <| List.map .distance tracks.current.trackpoints
                        in
                        profile tracks.current maxDistance model.fontSize model.trackHeight model.trackThickness model.waypointStrokeColor model.location model.showIntensity model.intensityTau
                            :: (if model.showWaypointEditor then
                                    [ Html.div []
                                        (tracks.current.waypoints
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

                                else
                                    []
                               )
                )
            ]
        ]


viewOptions :
    { show : Bool
    , showWaypointEditor : Bool
    , tracks : Maybe Tracks
    , fontSize : Float
    , trackHeight : Int
    , trackThickness : Float
    , waypointStrokeColor : String
    , location : Maybe LocationState
    , locationError : Maybe LocationError
    , trackingEnabled : Bool
    , trackingIntervalSec : Int
    , showIntensity : Bool
    , intensityTau : Float
    }
    -> Html Msg
viewOptions options =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "justify-content" "center"
        , Html.Attributes.style "overflow" "auto"
        , Html.Attributes.class "narrow"
        ]
        (if not options.show then
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
                            (List.concat
                                [ [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "upload GPX" OpenFileBrowser ]
                                , if options.tracks |> Maybe.map (\ts -> listPopulated ts.current.waypoints) |> Maybe.withDefault False then
                                    if options.showWaypointEditor then
                                        [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "HIDE EDITOR" (ShowWaypointEditor False) ]

                                    else
                                        [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "SHOW EDITOR" (ShowWaypointEditor True) ]

                                  else
                                    []
                                , if options.tracks |> Maybe.map (\ts -> listPopulated ts.prev) |> Maybe.withDefault False then
                                    [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "PREV" NavigateToPrevious ]

                                  else
                                    []
                                , if options.tracks |> Maybe.map (\ts -> listPopulated ts.next) |> Maybe.withDefault False then
                                    [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "NEXT" NavigateToNext ]

                                  else
                                    []
                                , [ optionGroup "Font size"
                                        [ Html.input
                                            [ Html.Attributes.type_ "range"
                                            , Html.Attributes.min "1"
                                            , Html.Attributes.max "50"
                                            , Html.Attributes.value <| String.fromFloat options.fontSize
                                            , Html.Events.onInput (String.toFloat >> Maybe.withDefault 15 >> UpdateFontSize)
                                            ]
                                            []
                                        ]
                                  , optionGroup "Track height"
                                        [ Html.input
                                            [ Html.Attributes.type_ "range"
                                            , Html.Attributes.min "1"
                                            , Html.Attributes.max "400"
                                            , Html.Attributes.value <| String.fromInt options.trackHeight
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
                                            , Html.Attributes.value <| String.fromFloat options.trackThickness
                                            , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1 >> UpdateTrackThickness)
                                            ]
                                            []
                                        ]
                                  , optionGroup "Waypoint stroke colour"
                                        [ Html.textarea
                                            [ Html.Attributes.placeholder "Waypoint stroke colour..."
                                            , Html.Attributes.value options.waypointStrokeColor
                                            , Html.Events.onInput <| WaypointStrokeColourChange
                                            ]
                                            []
                                        ]
                                  , optionGroup "Intensity"
                                        (List.concat
                                            [ [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ]
                                                    (if options.showIntensity then
                                                        "HIDE INTENSITY"

                                                     else
                                                        "SHOW INTENSITY"
                                                    )
                                                    (ShowIntensity (not options.showIntensity))
                                              ]
                                            , if options.showIntensity then
                                                [ Html.input
                                                    [ Html.Attributes.type_ "range"
                                                    , Html.Attributes.min "100"
                                                    , Html.Attributes.max "10000"
                                                    , Html.Attributes.step "50"
                                                    , Html.Attributes.value <| String.fromFloat options.intensityTau
                                                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 500 >> UpdateIntensityTau)
                                                    ]
                                                    []
                                                , Html.text ("\u{03C4} = " ++ String.fromFloat options.intensityTau ++ "m")
                                                ]

                                              else
                                                []
                                            ]
                                        )
                                  ]
                                , if options.tracks /= Nothing then
                                    List.concat
                                        [ [ Html.hr [] []
                                          , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "Refresh Location" RequestLocation
                                          , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ]
                                                (if options.trackingEnabled then
                                                    "Stop Tracking"

                                                 else
                                                    "Start Tracking"
                                                )
                                                ToggleTracking
                                          ]
                                        , if options.trackingEnabled then
                                            [ optionGroup ("Interval: " ++ String.fromInt options.trackingIntervalSec ++ "s")
                                                [ Html.input
                                                    [ Html.Attributes.type_ "range"
                                                    , Html.Attributes.min "10"
                                                    , Html.Attributes.max "300"
                                                    , Html.Attributes.step "10"
                                                    , Html.Attributes.value <| String.fromInt options.trackingIntervalSec
                                                    , Html.Events.onInput (String.toInt >> Maybe.withDefault 60 >> SetTrackingInterval)
                                                    ]
                                                    []
                                                ]
                                            ]

                                          else
                                            []
                                        , [ Html.p
                                                [ Html.Attributes.style "font-size" "0.8em"
                                                , Html.Attributes.style "margin" "0.5em 0"
                                                ]
                                                [ Html.text
                                                    (case options.locationError of
                                                        Just err ->
                                                            locationErrorToString err

                                                        Nothing ->
                                                            case options.location of
                                                                Just loc ->
                                                                    "Accuracy: " ++ String.fromFloat (toFloat (round (loc.accuracy * 10)) / 10) ++ "m"

                                                                Nothing ->
                                                                    "No location fix"
                                                    )
                                                ]
                                          ]
                                        ]

                                  else
                                    []
                                ]
                            )
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


profile : Track -> Float -> Float -> Int -> Float -> String -> Maybe LocationState -> Bool -> Float -> Html Msg
profile track maxDistance fontSize trackHeight trackThickness waypointStrokeColor maybeLocation showIntensity intensityTau =
    let
        -- TODO(ghanmer): combine these max folds to not iterate through twice
        maxElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.maximum <| List.map .elevation track.trackpoints

        minElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.minimum <| List.map .elevation track.trackpoints

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
            [ -- intensity shading
              if showIntensity then
                  renderIntensityShading (toFloat svgWidth) maxDistance (toFloat trackHeight) (computeIntensity intensityTau track.trackpoints)

              else
                  Svg.g [] []
            , -- waypoints
              Svg.g []
                (let
                    svgBottom =
                        String.fromInt svgHeight

                    paddedWaypointTextY =
                        String.fromInt <| trackHeight + 5
                 in
                 track.waypoints
                    |> List.concatMap
                        (\waypoint ->
                            let
                                x =
                                    calc.x waypoint.distance

                                y =
                                    calc.y <| interpolateWaypointElevation track.trackpoints waypoint - 5
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
              resolveElevationProfileSVGLine calc track.trackpoints (String.fromFloat trackThickness)
            , -- position marker
              case maybeLocation of
                Just loc ->
                    let
                        xPos =
                            calc.x loc.matchedDistance

                        yPos =
                            calc.y (interpolateWaypointElevation track.trackpoints { distance = loc.matchedDistance, name = "" })
                    in
                    Svg.g []
                        [ Svg.line
                            [ Svg.Attributes.x1 xPos
                            , Svg.Attributes.y1 "0"
                            , Svg.Attributes.x2 xPos
                            , Svg.Attributes.y2 (String.fromInt trackHeight)
                            , Svg.Attributes.stroke "dodgerblue"
                            , Svg.Attributes.strokeWidth "2"
                            , Svg.Attributes.opacity "0.7"
                            ]
                            []
                        , Svg.circle
                            [ Svg.Attributes.cx xPos
                            , Svg.Attributes.cy yPos
                            , Svg.Attributes.r "3.5"
                            , Svg.Attributes.fill "dodgerblue"
                            ]
                            []
                        ]

                Nothing ->
                    Svg.g [] []
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


interpolateWaypointElevation : List TrackPoint -> Waypoint -> Float
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


resolveElevationProfileSVGLine : XYCalculator -> List TrackPoint -> String -> Svg.Svg msg
resolveElevationProfileSVGLine calc profileData trackThicknessAttrValue =
    Svg.polyline
        [ Svg.Attributes.points
            (profileData
                |> List.map (\point -> calc.x point.distance ++ " " ++ calc.y point.elevation)
                |> String.join ", "
            )
        , Svg.Attributes.stroke "grey"
        , Svg.Attributes.strokeWidth trackThicknessAttrValue
        , Svg.Attributes.fill "none"
        ]
        []


-- Compute trail intensity at each trackpoint using an Exponential Weighted
-- Moving Average (EWMA) of the climbing-only grade signal.
--
-- The EWMA uses distance (not time) as its independent variable, with a
-- characteristic distance τ (tau) controlling how far back the "memory"
-- extends. At distance τ from a contribution, its weight has decayed to ~37%
-- (1/e). No lookahead is used — intensity at each point depends only on
-- current and historic data.
--
-- For each consecutive pair of trackpoints:
--   Δd  = distance[i] - distance[i-1]
--   grade = (elevation[i] - elevation[i-1]) / Δd
--   signal = max(0, grade)          -- climbing-only: descents contribute 0
--   decay = e^(-Δd / τ)             -- distance-weighted exponential decay
--   intensity[i] = decay × intensity[i-1] + (1 - decay) × signal
--
-- Intensity is initialized at 0 (fresh legs). The τ parameter controls
-- responsiveness: small τ tracks local steepness closely (spiky), large τ
-- produces a smoother signal reflecting sustained climbing effort.
computeIntensity : Float -> List TrackPoint -> List { distance : Float, intensity : Float }
computeIntensity tau trackPoints =
    case trackPoints of
        [] ->
            []

        first :: rest ->
            let
                ( _, result ) =
                    List.foldl
                        (\current ( ( prev, prevIntensity ), acc ) ->
                            let
                                deltaD =
                                    current.distance - prev.distance

                                -- Grade as a ratio (e.g. 0.10 = 10% grade).
                                -- Zero when points are co-located to avoid division by zero.
                                grade =
                                    if deltaD > 0 then
                                        (current.elevation - prev.elevation) / deltaD

                                    else
                                        0

                                -- Only uphill contributes to intensity; descents and
                                -- flats produce a zero signal that lets intensity decay.
                                climbingGrade =
                                    max 0 grade

                                -- Exponential decay factor: approaches 1 for closely-spaced
                                -- points (preserving history) and 0 for large gaps (resetting).
                                decay =
                                    e ^ (-deltaD / tau)

                                -- Standard EWMA update: blend previous intensity with the
                                -- current observation, weighted by distance-based decay.
                                newIntensity =
                                    decay * prevIntensity + (1 - decay) * climbingGrade
                            in
                            ( ( current, newIntensity )
                            , { distance = current.distance, intensity = newIntensity } :: acc
                            )
                        )
                        ( ( first, 0 ), [ { distance = first.distance, intensity = 0 } ] )
                        rest
            in
            List.reverse result


-- Render intensity shading as a row of SVG rectangles spanning the full chart
-- height. Each segment between consecutive points is filled with a green →
-- yellow → red color at 30% opacity.
--
-- Min-max normalization maps the least intense point to green (0) and the most
-- intense to red (1), always using the full color range regardless of τ or
-- route characteristics. When intensity is constant across the entire profile
-- (including the trivial case of an entirely flat route where all values are 0),
-- the range is zero and all segments render as green.
renderIntensityShading : Float -> Float -> Float -> List { distance : Float, intensity : Float } -> Svg.Svg msg
renderIntensityShading svgWidth maxDistance trackHeightFloat intensityPoints =
    let
        intensities =
            List.map .intensity intensityPoints

        minIntensity =
            List.minimum intensities |> Maybe.withDefault 0

        maxIntensity =
            List.maximum intensities |> Maybe.withDefault 0

        -- When max == min the intensity is constant and there is nothing
        -- meaningful to shade, so all segments map to 0 (green).
        intensityRange =
            maxIntensity - minIntensity

        svgWidthPerDistanceUnit =
            svgWidth / maxDistance

        xFloat distance =
            distance * svgWidthPerDistanceUnit
    in
    Svg.g []
        (List.map2
            (\a b ->
                let
                    normalized =
                        if intensityRange > 0 then
                            (b.intensity - minIntensity) / intensityRange

                        else
                            0

                    x1 =
                        xFloat a.distance

                    x2 =
                        xFloat b.distance
                in
                Svg.rect
                    [ Svg.Attributes.x (String.fromFloat x1)
                    , Svg.Attributes.y "0"
                    , Svg.Attributes.width (String.fromFloat (x2 - x1))
                    , Svg.Attributes.height (String.fromFloat trackHeightFloat)
                    , Svg.Attributes.fill (intensityColor normalized)
                    , Svg.Attributes.opacity "0.3"
                    ]
                    []
            )
            intensityPoints
            (List.drop 1 intensityPoints)
        )


-- Map a normalized intensity value to a green → yellow → red color string.
-- Input is clamped to [0, 1]:
--   0.0 → pure green  (rgb 0,255,0)
--   0.5 → pure yellow (rgb 255,255,0)
--   1.0 → pure red    (rgb 255,0,0)
-- Values above 1.0 (possible when a segment exceeds the normalization cap)
-- are clamped to red.
intensityColor : Float -> String
intensityColor t =
    let
        clamped =
            clamp 0 1 t

        -- Red channel: ramps linearly from 0 to 255 over the first half,
        -- then holds at 255 for the upper half.
        r =
            round
                (if clamped < 0.5 then
                    255 * clamped * 2

                 else
                    255
                )

        -- Green channel: holds at 255 for the lower half, then ramps
        -- linearly down to 0 over the upper half.
        g =
            round
                (if clamped < 0.5 then
                    255

                 else
                    255 * (1 - (clamped - 0.5) * 2)
                )
    in
    "rgb(" ++ String.fromInt r ++ "," ++ String.fromInt g ++ ",0)"


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



-- GPX API


type alias ElevationProfileDataResponse =
    List Track


decodeElevationProfileDataResponse : Json.Decode.Decoder ElevationProfileDataResponse
decodeElevationProfileDataResponse =
    Json.Decode.list
        (Json.Decode.map2 Track
            (Json.Decode.field "track" decodeTrackpoints)
            (Json.Decode.maybe (Json.Decode.field "waypoints" decodeWaypoints)
                |> Json.Decode.map (Maybe.withDefault [])
            )
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


encodeTracks : Tracks -> Json.Encode.Value
encodeTracks tracks =
    Json.Encode.object
        [ ( "previous", Json.Encode.list encodeTrack tracks.prev )
        , ( "current", encodeTrack tracks.current )
        , ( "next", Json.Encode.list encodeTrack tracks.next )
        ]


decodeTracks : Json.Decode.Decoder Tracks
decodeTracks =
    Json.Decode.map3 Tracks
        (Json.Decode.field "previous" (Json.Decode.list decodeTrack))
        (Json.Decode.field "current" decodeTrack)
        (Json.Decode.field "next" (Json.Decode.list decodeTrack))


encodeTrack : Track -> Json.Encode.Value
encodeTrack track =
    Json.Encode.object
        [ ( "trackpoints", encodeTrackpoints track.trackpoints )
        , ( "waypoints", encodeWaypoints track.waypoints )
        ]


decodeTrack : Json.Decode.Decoder Track
decodeTrack =
    Json.Decode.map2 Track
        (Json.Decode.field "trackpoints" decodeTrackpoints)
        (Json.Decode.field "waypoints" decodeWaypoints)


encodeTrackpoints : List TrackPoint -> Json.Encode.Value
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


decodeTrackpoints : Json.Decode.Decoder (List TrackPoint)
decodeTrackpoints =
    Json.Decode.list
        (Json.Decode.map4 TrackPoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "ele" Json.Decode.float)
            (Json.Decode.field "lat" Json.Decode.float)
            (Json.Decode.field "lon" Json.Decode.float)
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
        (maybeFromloadableResource model.tracks)
        model.gpxServerURLOverride
        (Just model.fontSize)
        (Just model.trackHeight)
        (Just model.trackThickness)
        (Just model.waypointStrokeColor)
        (Just model.trackingIntervalSec)
        (Just model.showIntensity)
        (Just model.intensityTau)


encodeSavedState : StoredState -> String
encodeSavedState state =
    Json.Encode.object
        (List.filterMap
            identity
            [ state.gpxServerURL |> Maybe.map (\url -> ( "gpxServerURL", Json.Encode.string url ))
            , state.fontSize |> Maybe.map (\size -> ( "fontSize", Json.Encode.float size ))
            , state.trackHeight |> Maybe.map (\height -> ( "trackHeight", Json.Encode.int height ))
            , state.trackThickness |> Maybe.map (\thickness -> ( "trackThickness", Json.Encode.float thickness ))
            , state.waypointStrokeColor |> Maybe.map (\colour -> ( "waypointStrokeColor", Json.Encode.string colour ))
            , state.tracks |> Maybe.map (\tracks -> ( "tracks", encodeTracks tracks ))
            , state.trackingIntervalSec |> Maybe.map (\interval -> ( "trackingIntervalSec", Json.Encode.int interval ))
            , state.showIntensity |> Maybe.map (\show -> ( "showIntensity", Json.Encode.bool show ))
            , state.intensityTau |> Maybe.map (\tau -> ( "intensityTau", Json.Encode.float tau ))
            ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : Json.Decode.Decoder StoredState
storedStateDecoder =
    Json.Decode.map6 StoredState
        (Json.Decode.maybe (Json.Decode.field "tracks" decodeTracks))
        (Json.Decode.maybe (Json.Decode.field "gpxServerURL" Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field "fontSize" Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "trackHeight" Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field "trackThickness" Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "waypointStrokeColor" Json.Decode.string))
        |> andMap (Json.Decode.maybe (Json.Decode.field "trackingIntervalSec" Json.Decode.int))
        |> andMap (Json.Decode.maybe (Json.Decode.field "showIntensity" Json.Decode.bool))
        |> andMap (Json.Decode.maybe (Json.Decode.field "intensityTau" Json.Decode.float))


andMap : Json.Decode.Decoder a -> Json.Decode.Decoder (a -> b) -> Json.Decode.Decoder b
andMap =
    Json.Decode.map2 (|>)


port storeState : String -> Cmd msg


port requestLocation : () -> Cmd msg


port receiveLocation : (Json.Decode.Value -> msg) -> Sub msg



-- LOCATION


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


findNearestTrackPoint : LatLon -> List TrackPoint -> Maybe TrackPoint
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


listPopulated : List a -> Bool
listPopulated list =
    List.length list > 0
