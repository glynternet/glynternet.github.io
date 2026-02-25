port module Main exposing (main)

import Browser
import Browser.Navigation
import Dict
import File exposing (File)
import File.Select
import GpxApi
import Location
import PositionalTracks exposing (PositionalTracks)
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Json.Encode
import List.Extra
import String
import Svg
import Svg.Attributes
import Task
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
        , receiveElevationProfileData ElevationProfileResponseStringReceived
        ]



-- MODEL


type alias Model =
    { tracks : LoadableResource PositionalTracks
    , showOptions : Bool
    , showWaypointEditor : Bool
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
    , categoryFilterEnabled : Bool
    , filteredCategories : Dict.Dict String Bool
    , manualPosition : Maybe Float
    }


type alias Track =
    GpxApi.Track


trackWithWaypoints : Track -> List Waypoint -> Track
trackWithWaypoints track waypoints =
    { track | waypoints = waypoints }


trackUpdateWaypoint : Track -> Int -> (Waypoint -> Waypoint) -> Track
trackUpdateWaypoint track i updateWaypoint =
    trackWithWaypoints track <| List.Extra.updateAt i updateWaypoint track.waypoints


type alias TrackPoint =
    GpxApi.TrackPoint


type alias Waypoint =
    GpxApi.Waypoint


type alias LatLon =
    Location.LatLon


type alias LocationState =
    Location.LocationState


type alias LocationError =
    Location.LocationError


type alias StoredState =
    { tracks : Maybe PositionalTracks
    , fontSize : Maybe Float
    , trackHeight : Maybe Int
    , trackThickness : Maybe Float
    , waypointStrokeColor : Maybe String
    , trackingIntervalSec : Maybe Int
    , showIntensity : Maybe Bool
    , intensityTau : Maybe Float
    , categoryFilterEnabled : Maybe Bool
    , filteredCategories : Maybe (Dict.Dict String Bool)
    , manualPosition : Maybe Float
    }


storedStateModel : StoredState -> Model
storedStateModel state =
    { tracks = loadableResourceFromMaybe state.tracks
    , showOptions = True
    , showWaypointEditor = False
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
    , categoryFilterEnabled = Maybe.withDefault False state.categoryFilterEnabled
    , filteredCategories = Maybe.withDefault Dict.empty state.filteredCategories
    , manualPosition = state.manualPosition
    }


defaultStoredState : StoredState
defaultStoredState =
    StoredState Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing


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
    | GPXStringed String
    | ElevationProfileResponseStringReceived String
    | CategoryEnabled String Bool
    | UpdateCategoryFilterEnabled Bool
    | SetAllCategoriesEnabled Bool
    | UpdateManualPosition (Maybe Float)


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
                            , Task.perform GPXStringed (File.toString file)
                            ]
                    )

        Ignore ->
            ( model, Cmd.none )

        NavigateToPrevious ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model | tracks = Loaded (PositionalTracks.navigatePrevious tracks) }

                _ ->
                    ( model, Cmd.none )

        NavigateToNext ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model | tracks = Loaded (PositionalTracks.navigateNext tracks) }

                _ ->
                    ( model, Cmd.none )

        WaypointNameChange i name ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model
                            | tracks =
                                Loaded <|
                                    PositionalTracks.updateCurrent
                                        (\current -> trackUpdateWaypoint current i (\w -> { w | name = name }))
                                        tracks
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
                                    PositionalTracks.updateCurrent
                                        (\current -> trackUpdateWaypoint current i (\w -> { w | distance = dist }))
                                        tracks
                        }

                _ ->
                    ( model, Cmd.none )

        DeleteWaypoint i ->
            case model.tracks of
                Loaded tracks ->
                    updateModel { model | tracks = Loaded <| PositionalTracks.updateCurrent (\current -> trackWithWaypoints current (List.Extra.removeAt i current.waypoints)) tracks }

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
                                    Location.LatLon pos.lat pos.lon

                                matchedDist =
                                    findNearestTrackPoint gpsPos tracks.current.trackpoints
                                        |> Maybe.map .distance
                                        |> Maybe.withDefault 0
                            in
                            ( { model
                                | location = Just (Location.LocationState gpsPos pos.accuracy matchedDist)
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
                    ( { model | locationError = Just Location.PositionUnavailable }, Cmd.none )

        GPXStringed gpxContent ->
            ( model, calculateElevationProfileData gpxContent )

        ElevationProfileResponseStringReceived string ->
            case Json.Decode.decodeString (GpxApi.decodeResult GpxApi.decodeElevationProfileDataResponse) string of
                Err errMsg ->
                    updateModel
                        { model | tracks = Error ("parsing result from GPX response: " ++ Json.Decode.errorToString errMsg) }

                Ok typedResult ->
                    case typedResult of
                        Err errMsg ->
                            updateModel
                                { model | tracks = Error ("getting profile data from GPX: " ++ errMsg) }

                        Ok tracks ->
                            let
                                allWaypoints =
                                    List.concatMap .waypoints tracks

                                categories =
                                    initialFilteredCategories allWaypoints
                            in
                            updateModel
                                { model
                                    | tracks =
                                        case PositionalTracks.fromList tracks of
                                            Nothing ->
                                                Error "No tracks available in uploaded GPX 😢"

                                            Just positionalTracks ->
                                                Loaded positionalTracks
                                    , filteredCategories = categories
                                }

        CategoryEnabled category enabled ->
            updateModel { model | filteredCategories = Dict.insert category enabled model.filteredCategories }

        UpdateCategoryFilterEnabled enabled ->
            updateModel { model | categoryFilterEnabled = enabled }

        SetAllCategoriesEnabled enabled ->
            updateModel { model | filteredCategories = Dict.map (\_ _ -> enabled) model.filteredCategories }

        UpdateManualPosition pos ->
            updateModel { model | manualPosition = pos }


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    ( model, storeState (storedStateFromModel model |> encodeSavedState) )


effectivePosition : Model -> Maybe Float
effectivePosition model =
    case model.manualPosition of
        Just _ ->
            model.manualPosition

        Nothing ->
            model.location |> Maybe.map .matchedDistance


unknownCategory : String
unknownCategory =
    ""


initialFilteredCategories : List Waypoint -> Dict.Dict String Bool
initialFilteredCategories =
    List.foldl
        (\w ( acc, includeUnknown ) ->
            if List.isEmpty w.categories then
                ( acc, True )

            else
                ( List.foldl (\cat d -> Dict.insert cat True d) acc w.categories
                , includeUnknown
                )
        )
        ( Dict.empty, False )
        >> (\( d, hasUnknown ) ->
                if hasUnknown then
                    Dict.insert unknownCategory True d

                else
                    d
           )


filterWaypointsByCategory : Bool -> Dict.Dict String Bool -> List Waypoint -> List Waypoint
filterWaypointsByCategory filterEnabled categories waypoints =
    if not filterEnabled then
        waypoints

    else
        List.filterMap
            (\w ->
                let
                    includeCategory cat =
                        Dict.get cat categories |> Maybe.withDefault True
                in
                case w.categories of
                    [] ->
                        if includeCategory unknownCategory then
                            Just w

                        else
                            Nothing

                    cats ->
                        if List.any includeCategory cats then
                            Just w

                        else
                            Nothing
            )
            waypoints



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
                , categoryFilterEnabled = model.categoryFilterEnabled
                , filteredCategories = model.filteredCategories
                , manualPosition = model.manualPosition
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
                        [ viewErrorPanel <|
                            ("There was an error creating your profile. Please fix any error and try again 😇\n\nError: "
                                ++ (if String.length err > 1000 then
                                        String.left 500 err ++ "...\n\n..." ++ String.right 500 err

                                    else
                                        err
                                   )
                            )
                        ]

                    Loaded tracks ->
                        let
                            maxDistance =
                                Maybe.withDefault 1 <| List.maximum <| List.map .distance tracks.current.trackpoints

                            filteredWaypoints =
                                filterWaypointsByCategory model.categoryFilterEnabled model.filteredCategories tracks.current.waypoints
                        in
                        profile { trackpoints = tracks.current.trackpoints, waypoints = filteredWaypoints } maxDistance model.fontSize model.trackHeight model.trackThickness model.waypointStrokeColor (effectivePosition model) model.showIntensity model.intensityTau
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
    , tracks : Maybe PositionalTracks
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
    , categoryFilterEnabled : Bool
    , filteredCategories : Dict.Dict String Bool
    , manualPosition : Maybe Float
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
                                  , optionGroup "Waypoint categories"
                                        (Html.select
                                            [ Html.Events.onInput
                                                (\val ->
                                                    case val of
                                                        "all" ->
                                                            UpdateCategoryFilterEnabled False

                                                        _ ->
                                                            UpdateCategoryFilterEnabled True
                                                )
                                            ]
                                            [ Html.option
                                                [ Html.Attributes.value "all"
                                                , Html.Attributes.selected (not options.categoryFilterEnabled)
                                                ]
                                                [ Html.text "all" ]
                                            , Html.option
                                                [ Html.Attributes.value "filtered"
                                                , Html.Attributes.selected options.categoryFilterEnabled
                                                ]
                                                [ Html.text "filtered" ]
                                            ]
                                            :: (if options.categoryFilterEnabled then
                                                    [ Html.fieldset []
                                                        ((options.filteredCategories
                                                            |> Dict.toList
                                                            |> List.map
                                                                (\( cat, included ) ->
                                                                    checkbox included
                                                                        (CategoryEnabled cat (not included))
                                                                        (if cat /= unknownCategory then
                                                                            cat

                                                                         else
                                                                            "unknown"
                                                                        )
                                                                )
                                                         )
                                                            ++ [ Html.button [ Html.Events.onClick <| SetAllCategoriesEnabled True ] [ Html.text "All" ]
                                                               , Html.button [ Html.Events.onClick <| SetAllCategoriesEnabled False ] [ Html.text "None" ]
                                                               ]
                                                        )
                                                    ]

                                                else
                                                    []
                                               )
                                        )
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
                                                , Html.text ("τ = " ++ String.fromFloat options.intensityTau ++ "m")
                                                ]

                                              else
                                                []
                                            ]
                                        )
                                  , optionGroup "Position"
                                        (let
                                            maxDist =
                                                options.tracks
                                                    |> Maybe.andThen (\ts -> List.maximum (List.map .distance ts.current.trackpoints))
                                                    |> Maybe.withDefault 1
                                         in
                                         List.concat
                                            [ [ Html.input
                                                    [ Html.Attributes.type_ "range"
                                                    , Html.Attributes.min "0"
                                                    , Html.Attributes.max (String.fromFloat maxDist)
                                                    , Html.Attributes.step "100"
                                                    , Html.Attributes.value (options.manualPosition |> Maybe.map String.fromFloat |> Maybe.withDefault "0")
                                                    , Html.Events.onInput (String.toFloat >> Maybe.map Just >> Maybe.withDefault Nothing >> UpdateManualPosition)
                                                    ]
                                                    []
                                              ]
                                            , case options.manualPosition of
                                                Just _ ->
                                                    [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "Clear position" (UpdateManualPosition Nothing) ]

                                                Nothing ->
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


checkbox : Bool -> Msg -> String -> Html Msg
checkbox checked msg label =
    Html.div []
        [ Html.input [ Html.Attributes.type_ "checkbox", Html.Events.onClick msg, Html.Attributes.checked checked ] []
        , Html.label [ Html.Events.onClick msg ] [ Html.text label ]
        ]


profile : Track -> Float -> Float -> Int -> Float -> String -> Maybe Float -> Bool -> Float -> Html Msg
profile track maxDistance fontSize trackHeight trackThickness waypointStrokeColor maybePosition showIntensity intensityTau =
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
                                    calc.y <| interpolateWaypointElevation track.trackpoints waypoint.distance - 5
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
              case maybePosition of
                Just posDistance ->
                    let
                        xPos =
                            calc.x posDistance

                        yPos =
                            calc.y (interpolateWaypointElevation track.trackpoints posDistance)
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


interpolateWaypointElevation : List TrackPoint -> Float -> Float
interpolateWaypointElevation trackPoints distance =
    case trackPoints of
        [] ->
            0

        a :: others ->
            if a.distance >= distance then
                a.elevation

            else
                case others of
                    [] ->
                        a.elevation

                    b :: _ ->
                        if b.distance >= distance then
                            -- properly interpolate here
                            a.elevation

                        else
                            interpolateWaypointElevation others distance


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



-- ENCODE/DECODE MODEL


encodePositionalTracks : PositionalTracks -> Json.Encode.Value
encodePositionalTracks =
    PositionalTracks.encode


decodePositionalTracks : Json.Decode.Decoder PositionalTracks
decodePositionalTracks =
    PositionalTracks.decoder



-- STATE


storedStateFromModel : Model -> StoredState
storedStateFromModel model =
    StoredState
        (maybeFromloadableResource model.tracks)
        (Just model.fontSize)
        (Just model.trackHeight)
        (Just model.trackThickness)
        (Just model.waypointStrokeColor)
        (Just model.trackingIntervalSec)
        (Just model.showIntensity)
        (Just model.intensityTau)
        (Just model.categoryFilterEnabled)
        (Just model.filteredCategories)
        model.manualPosition


encodeSavedState : StoredState -> String
encodeSavedState state =
    Json.Encode.object
        (List.filterMap
            identity
            [ state.fontSize |> Maybe.map (\size -> ( "fontSize", Json.Encode.float size ))
            , state.trackHeight |> Maybe.map (\height -> ( "trackHeight", Json.Encode.int height ))
            , state.trackThickness |> Maybe.map (\thickness -> ( "trackThickness", Json.Encode.float thickness ))
            , state.waypointStrokeColor |> Maybe.map (\colour -> ( "waypointStrokeColor", Json.Encode.string colour ))
            , state.tracks |> Maybe.map (\tracks -> ( "tracks", encodePositionalTracks tracks ))
            , state.trackingIntervalSec |> Maybe.map (\interval -> ( "trackingIntervalSec", Json.Encode.int interval ))
            , state.showIntensity |> Maybe.map (\show -> ( "showIntensity", Json.Encode.bool show ))
            , state.intensityTau |> Maybe.map (\tau -> ( "intensityTau", Json.Encode.float tau ))
            , state.categoryFilterEnabled |> Maybe.map (\enabled -> ( "categoryFilterEnabled", Json.Encode.bool enabled ))
            , state.filteredCategories |> Maybe.map (\cats -> ( "filteredCategories", Json.Encode.dict identity Json.Encode.bool cats ))
            , state.manualPosition |> Maybe.map (\pos -> ( "manualPosition", Json.Encode.float pos ))
            ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : Json.Decode.Decoder StoredState
storedStateDecoder =
    Json.Decode.map5 StoredState
        (Json.Decode.maybe (Json.Decode.field "tracks" decodePositionalTracks))
        (Json.Decode.maybe (Json.Decode.field "fontSize" Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "trackHeight" Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field "trackThickness" Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field "waypointStrokeColor" Json.Decode.string))
        |> andMap (Json.Decode.maybe (Json.Decode.field "trackingIntervalSec" Json.Decode.int))
        |> andMap (Json.Decode.maybe (Json.Decode.field "showIntensity" Json.Decode.bool))
        |> andMap (Json.Decode.maybe (Json.Decode.field "intensityTau" Json.Decode.float))
        |> andMap (Json.Decode.maybe (Json.Decode.field "categoryFilterEnabled" Json.Decode.bool))
        |> andMap (Json.Decode.maybe (Json.Decode.field "filteredCategories" (Json.Decode.dict Json.Decode.bool)))
        |> andMap (Json.Decode.maybe (Json.Decode.field "manualPosition" Json.Decode.float))


andMap : Json.Decode.Decoder a -> Json.Decode.Decoder (a -> b) -> Json.Decode.Decoder b
andMap =
    Json.Decode.map2 (|>)


port storeState : String -> Cmd msg


port requestLocation : () -> Cmd msg


port receiveLocation : (Json.Decode.Value -> msg) -> Sub msg



-- LOCATION


findNearestTrackPoint : LatLon -> List TrackPoint -> Maybe TrackPoint
findNearestTrackPoint =
    Location.findNearestTrackPoint


decodeLocationResult : Json.Decode.Decoder (Result LocationError { lat : Float, lon : Float, accuracy : Float })
decodeLocationResult =
    Location.decodeLocationResult


locationErrorToString : LocationError -> String
locationErrorToString =
    Location.locationErrorToString



-- TODO: can this be bytes or jaon.Value (ish) types to have less indirection?!


port calculateElevationProfileData : String -> Cmd msg


port receiveElevationProfileData : (String -> msg) -> Sub msg



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


listPopulated : List a -> Bool
listPopulated list =
    List.length list > 0
