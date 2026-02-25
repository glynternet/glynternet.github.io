port module Main exposing (storeState)

import Browser
import Dict
import Dropdown
import File
import File.Select
import GpxApi
import Html exposing (Attribute, Html)
import Location
import Html.Attributes
import Html.Events
import Json.Decode
import Json.Encode
import Round
import String
import Svg
import Svg.Attributes
import Task
import Time



-- MAIN


main =
    Browser.document
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 1500 (always AnimationTick)
        , receiveElevationProfileData WasmResponseReceived
        , receiveLocation LocationReceived
        , if model.trackingEnabled then
            Time.every (toFloat model.trackingIntervalSec * 1000) LocationTick

          else
            Sub.none
        ]



-- MODEL


type alias StoredState =
    { waypoints : Maybe (List GpxApi.Waypoint)
    , totalDistanceDisplay : Maybe String
    , lastReferencePoint : Maybe Float
    , categoryFilterEnabled : Maybe Bool
    , filteredCategories : Maybe (Dict.Dict String Bool)
    , itemSpacing : Maybe Int
    , distanceDetail : Maybe Int
    , showStartFinish : Maybe Bool
    , showOptions : Maybe Bool
    , finishDistance : Maybe Float
    , trackingIntervalSec : Maybe Int
    }


type alias Model =
    { page : Page
    , gpxError : Maybe String
    , showOptions : Bool
    , cuesViewOptions : CuesViewOptions
    , location : Maybe Location.LocationState
    , locationError : Maybe Location.LocationError
    , trackingEnabled : Bool
    , trackingIntervalSec : Int
    }


type Page
    = WelcomePage Bool
    | GetStartedPage
    | CuesheetPage CuesModel


type alias CuesModel =
    { waypoints : List GpxApi.Waypoint
    , waypointOptions : WaypointsOptions
    , showStartFinish : Bool
    , finishDistance : Float
    , trackpoints : List GpxApi.TrackPoint
    }


type alias WaypointsOptions =
    { -- TODO: combine filter enabled and dict into single Maybe then deserialise from null or object
      categoryFilterEnabled : Bool
    , filteredCategories : Dict.Dict String Bool
    }


type alias CuesViewOptions =
    { totalDistanceDisplay : TotalDistanceDisplay
    , referencePoint : Float
    , position : Float
    , itemSpacing : Int
    , distanceDetail : Int
    }


type TotalDistanceDisplay
    = FromZero
    | ToFinish
    | ToPoint
    | None


unknownCategory =
    ""


startFinishCategory =
    "Start/Finish"


type Info
    = InfoWaypoint GpxApi.Waypoint
    | Ride Float


init : Maybe Json.Decode.Value -> ( Model, Cmd Msg )
init maybeState =
    (maybeState
        |> Maybe.map
            (Json.Decode.decodeValue (storedStateDecoder longFieldNames)
                -- TODO: handle error
                >> Result.withDefault (StoredState Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing)
                >> storedStateModel
            )
        -- TODO(glynternet): best default value for last reference point/?
        |> Maybe.withDefault (Model (WelcomePage False) Maybe.Nothing True (CuesViewOptions FromZero 1000 0 defaultSpacing defaultDistanceDetail) Nothing Nothing False 60)
    )
        |> updateModel


storedStateModel : StoredState -> Model
storedStateModel state =
    Model
        (state.waypoints
            |> Maybe.map
                (\ws ->
                    CuesModel ws
                        (WaypointsOptions
                            (state.categoryFilterEnabled |> Maybe.withDefault False)
                            (state.filteredCategories |> Maybe.withDefault (initialFilteredCategories ws))
                        )
                        (state.showStartFinish |> Maybe.withDefault False)
                        (state.finishDistance |> Maybe.withDefault 0)
                        []
                        |> CuesheetPage
                )
            |> Maybe.withDefault (WelcomePage False)
        )
        Maybe.Nothing
        (state.showOptions |> Maybe.withDefault True)
        (CuesViewOptions
            -- TODO(glynternet): store "to point" state
            (state.totalDistanceDisplay |> Maybe.andThen parseTotalDistanceDisplay |> Maybe.withDefault FromZero)
            (state.lastReferencePoint |> Maybe.withDefault 1000)
            -- TODO(glynternet): best default or getting last point here?
            0
            (Maybe.withDefault defaultSpacing state.itemSpacing)
            (Maybe.withDefault defaultDistanceDetail state.distanceDetail)
        )
        Nothing
        Nothing
        False
        (Maybe.withDefault 60 state.trackingIntervalSec)


type Msg
    = NoOp
    | ShowPage Page
    | CategoryEnabled String Bool
    | ShowOptions Bool
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdateCategoryFilterEnabled Bool
    | UpdatePosition Float
    | UpdateReferencePoint Float
    | UpdateItemSpacing Int
    | UpdateDistanceDetail Int
    | OpenFileBrowser
    | FileUploaded File.File
    | UpdateShowStartFinish Bool
    | SetAllCategoriesEnabled Bool
    | AnimationTick
    | LocationTick Time.Posix
    | LocationReceived Json.Decode.Value
    | RequestLocation
    | ToggleTracking
    | SetTrackingInterval Int
    | GPXStringed String
    | WasmResponseReceived String


initialWaypointOptions : List GpxApi.Waypoint -> WaypointsOptions
initialWaypointOptions waypoints =
    WaypointsOptions False (initialFilteredCategories waypoints)


initialFilteredCategories : List GpxApi.Waypoint -> Dict.Dict String Bool
initialFilteredCategories =
    List.foldl
        (\el ( waypointsIterationCurrent, includeUnknown ) ->
            if List.isEmpty el.categories then
                ( waypointsIterationCurrent, True )

            else
                ( List.foldl
                    (\cat waypointIterationCurrent -> Dict.insert cat True waypointIterationCurrent)
                    waypointsIterationCurrent
                    el.categories
                , includeUnknown
                )
        )
        ( Dict.empty, False )
        >> (\base ->
                case base of
                    ( d, True ) ->
                        Dict.insert unknownCategory True d

                    ( d, False ) ->
                        d
           )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ShowPage page ->
            updateModel { model | page = page }

        CategoryEnabled cat enabled ->
            case model.page of
                CuesheetPage cuesModel ->
                    let
                        options =
                            cuesModel.waypointOptions

                        newCuesModel =
                            { cuesModel | waypointOptions = { options | filteredCategories = Dict.insert cat enabled cuesModel.waypointOptions.filteredCategories } }
                    in
                    updateCuesModel model newCuesModel

                _ ->
                    ( model, Cmd.none )

        SetAllCategoriesEnabled enabled ->
            case model.page of
                CuesheetPage cuesModel ->
                    let
                        options =
                            cuesModel.waypointOptions

                        newCuesModel =
                            { cuesModel | waypointOptions = { options | filteredCategories = Dict.map (\_ _ -> enabled) options.filteredCategories } }
                    in
                    updateCuesModel model newCuesModel

                _ ->
                    ( model, Cmd.none )

        ShowOptions show ->
            updateModel { model | showOptions = show }

        UpdateTotalDistanceDisplay maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\selection ->
                        let
                            options =
                                model.cuesViewOptions
                        in
                        updateModel { model | cuesViewOptions = { options | totalDistanceDisplay = selection } }
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdateCategoryFilterEnabled enabled ->
            case model.page of
                CuesheetPage cuesModel ->
                    let
                        options =
                            cuesModel.waypointOptions

                        newCuesModel =
                            { cuesModel | waypointOptions = { options | categoryFilterEnabled = enabled } }
                    in
                    updateCuesModel model newCuesModel

                _ ->
                    ( model, Cmd.none )

        UpdatePosition position ->
            let
                options =
                    model.cuesViewOptions
            in
            updateModel { model | cuesViewOptions = { options | position = position } }

        UpdateReferencePoint point ->
            let
                options =
                    model.cuesViewOptions
            in
            updateModel { model | cuesViewOptions = { options | referencePoint = point } }

        UpdateItemSpacing spacing ->
            let
                options =
                    model.cuesViewOptions
            in
            updateModel { model | cuesViewOptions = { options | itemSpacing = spacing } }

        UpdateDistanceDetail detail ->
            let
                options =
                    model.cuesViewOptions
            in
            updateModel { model | cuesViewOptions = { options | distanceDetail = detail } }

        UpdateShowStartFinish show ->
            case model.page of
                CuesheetPage cuesModel ->
                    updateCuesModel model { cuesModel | showStartFinish = show }

                _ ->
                    ( model, Cmd.none )

        OpenFileBrowser ->
            ( model, File.Select.file [ "application/gpx+xml" ] FileUploaded )

        FileUploaded file ->
            ( { model | gpxError = Maybe.Nothing }
            , Task.perform GPXStringed (File.toString file)
            )

        NoOp ->
            ( model, Cmd.none )

        AnimationTick ->
            case model.page of
                WelcomePage val ->
                    ( { model | page = WelcomePage (not val) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        LocationTick _ ->
            ( model, requestLocation () )

        LocationReceived value ->
            case Json.Decode.decodeValue Location.decodeLocationResult value of
                Ok (Ok pos) ->
                    case model.page of
                        CuesheetPage cuesModel ->
                            let
                                gpsPos =
                                    Location.LatLon pos.lat pos.lon

                                matchedDist =
                                    Location.findNearestTrackPoint gpsPos cuesModel.trackpoints
                                        |> Maybe.map .distance
                                        |> Maybe.withDefault 0

                                options =
                                    model.cuesViewOptions
                            in
                            updateModel
                                { model
                                    | location = Just (Location.LocationState gpsPos pos.accuracy matchedDist)
                                    , locationError = Nothing
                                    , cuesViewOptions = { options | position = matchedDist }
                                }

                        _ ->
                            ( { model | locationError = Nothing }, Cmd.none )

                Ok (Err locErr) ->
                    ( { model | locationError = Just locErr }, Cmd.none )

                -- JSON decode failure; treat as unavailable
                Err _ ->
                    ( { model | locationError = Just Location.PositionUnavailable }, Cmd.none )

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

        GPXStringed gpxContent ->
            ( model, calculateElevationProfileData gpxContent )

        WasmResponseReceived string ->
            case Json.Decode.decodeString (GpxApi.decodeResult GpxApi.decodeElevationProfileDataResponse) string of
                Err errMsg ->
                    ( { model | gpxError = Maybe.Just ("parsing result from GPX response: " ++ Json.Decode.errorToString errMsg) }, Cmd.none )

                Ok typedResult ->
                    case typedResult of
                        Err errMsg ->
                            ( { model | gpxError = Maybe.Just errMsg }, Cmd.none )

                        Ok tracks ->
                            case tracks of
                                [ track ] ->
                                    let
                                        waypoints =
                                            track.waypoints
                                                |> List.sortBy .distance

                                        trackEndDistance =
                                            List.head (List.reverse track.trackpoints) |> Maybe.map .distance |> Maybe.withDefault 0

                                        cuesModel =
                                            initialCuesModel waypoints trackEndDistance track.trackpoints
                                    in
                                    { model | page = CuesheetPage cuesModel, gpxError = Maybe.Nothing } |> updateModel

                                [] ->
                                    ( { model | gpxError = Maybe.Just "No tracks found in GPX file" }, Cmd.none )

                                _ ->
                                    ( { model | gpxError = Maybe.Just "Multiple tracks found in GPX file; only single-track GPX files are supported" }, Cmd.none )


updateCuesModel : Model -> CuesModel -> ( Model, Cmd Msg )
updateCuesModel model cuesModel =
    updateModel <| { model | page = CuesheetPage cuesModel }


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    ( model, storeState (encodeSavedState longFieldNames model) )


initialCuesModel : List GpxApi.Waypoint -> Float -> List GpxApi.TrackPoint -> CuesModel
initialCuesModel waypoints trackFinish trackpoints =
    let
        sortedWaypoints =
            List.sortBy .distance waypoints
    in
    CuesModel sortedWaypoints (initialWaypointOptions sortedWaypoints) True trackFinish trackpoints



-- VIEW


view : Model -> Browser.Document Msg
view model =
    -- TODO: better title plz
    Browser.Document "Cuesheet"
        [ case model.page of
            CuesheetPage cuesheetModel ->
                Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "row"
                        , Html.Attributes.class "page"
                        , Html.Attributes.style "height" "100%"
                        ]
                        (let
                            waypointsWithStartFinish =
                                if cuesheetModel.showStartFinish then
                                    injectStartFinish cuesheetModel.finishDistance cuesheetModel.waypoints

                                else
                                    cuesheetModel.waypoints
                         in
                         [ viewOptions model.showOptions
                            (List.head (List.reverse waypointsWithStartFinish) |> Maybe.map .distance)
                            cuesheetModel.waypointOptions
                            cuesheetModel.showStartFinish
                            model.cuesViewOptions
                            model.gpxError
                            model.location
                            model.locationError
                            model.trackingEnabled
                            model.trackingIntervalSec
                         , Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.class "wide"
                            , Html.Attributes.style "height" "100%"
                            , Html.Attributes.style "justify-content" "center"
                            ]
                            [ cuesheet (cues cuesheetModel.waypointOptions waypointsWithStartFinish) model.cuesViewOptions cuesheetModel.finishDistance
                            ]
                         ]
                        )

            WelcomePage val ->
                welcomePage val

            GetStartedPage ->
                getStartedPage model.gpxError
        ]



welcomePage : Bool -> Html Msg
welcomePage toGo =
    let
        climbType =
            "CLIMB"

        cafeType =
            "CAFE"

        waterType =
            "WATER"

        exampleWaypoints =
            [ GpxApi.Waypoint 56100 "Blue shoes" [ cafeType ]
            , GpxApi.Waypoint 56300 "Lungburner" [ climbType ]
            , GpxApi.Waypoint 63700 "Steep Street" [ climbType ]
            , GpxApi.Waypoint 98300 "Foosville fountain" [ waterType, cafeType ]
            , GpxApi.Waypoint 198200 "Cosy hedge" [ "😴" ]
            , GpxApi.Waypoint 243800 "Legburner" [ climbType ]
            ]
    in
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "flex-center"
        , Html.Attributes.class "column"
        ]
        (List.concat
            [ [ Html.h2 [] [ Html.text "Cuesheet builder" ]
              , Html.br [] []
              , Html.h3 [] [ Html.text "Features" ]
              , Html.br [] []
              , Html.ul []
                    [ Html.li [] [ Html.text "Customise information level" ]
                    , Html.li [] [ Html.text "Compact or spacious view" ]
                    , Html.li [] [ Html.text "User-defined waypoint categories" ]
                    , Html.li [] [ Html.text "Filter waypoint categories" ]
                    , Html.li [] [ Html.text "...and more." ]
                    ]
              , Html.br [] []
              , Html.br [] []
              , viewButton "Get started..." <| ShowPage GetStartedPage
              , Html.br [] []
              , Html.br [] []
              , Html.h3 [] [ Html.text "...or see some examples" ]
              , Html.br [] []
              , Html.br [] []
              , Html.div
                    [ Html.Attributes.style "width" "100%"
                    , Html.Attributes.style "justify-content" "space-evenly"
                    , Html.Attributes.class "flex-container"
                    , Html.Attributes.class "flex-center"
                    , Html.Attributes.class "flex-wrap"
                    , Html.Attributes.class "wide-row-narrow-column"
                    ]
                    (List.map (\( desc, waypointModifier, opts ) -> Html.div [] [ Html.h4 [ Html.Attributes.style "text-align" "center" ] [ Html.text desc ], cuesheet (waypointModifier (injectStartFinish 273500 exampleWaypoints)) opts 273500 ])
                        [ if toGo then
                            ( "Distance to go", identity, CuesViewOptions ToFinish 1000 0 defaultSpacing defaultDistanceDetail )

                          else
                            ( "Distance from zero", identity, CuesViewOptions FromZero 1000 0 defaultSpacing defaultDistanceDetail )
                        , ( "Custom categories"
                          , List.map
                                (\w ->
                                    { w
                                        | categories =
                                            List.map
                                                (\cat ->
                                                    Dict.get cat (Dict.fromList [ ( cafeType, "☕" ), ( climbType, "⛰️" ), ( waterType, "🚰" ) ])
                                                        |> Maybe.withDefault cat
                                                )
                                                w.categories
                                    }
                                )
                          , CuesViewOptions None 1000 0 defaultSpacing defaultDistanceDetail
                          )
                        , ( "Custom spacing", identity, CuesViewOptions None 1000 0 (defaultSpacing - 10) defaultDistanceDetail )
                        , ( "Filter categories", cues (WaypointsOptions True (initialFilteredCategories exampleWaypoints |> Dict.map (\typ _ -> List.member typ [ unknownCategory, climbType, waterType ]))), CuesViewOptions None 1000 0 defaultSpacing defaultDistanceDetail )
                        ]
                    )
              ]
            ]
        )


getStartedPage : Maybe String -> Html Msg
getStartedPage gpxError =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "flex-center"
        , Html.Attributes.class "column"
        ]
        (List.concat
            [ [ Html.h2 [] [ Html.text "Cuesheet builder" ]
              , Html.br [] []
              , Html.h3 [] [ Html.text "Instructions" ]
              , Html.br [] []
              , Html.p [] [ Html.text "To make your cuesheet," ]
              , Html.p [] [ Html.text "upload a GPX file containing waypoints." ]
              , Html.p [] [ Html.text "Waypoints from the GPX will be used as cue points." ]
              , Html.br [] []
              , viewButton "upload GPX" OpenFileBrowser
              ]
            , gpxError |> Maybe.map (\err -> [ Html.br [] [], viewGpxErrorPanel err ]) |> Maybe.withDefault []
            , [ Html.br [] []
              , Html.br [] []
              ]
            ]
        )


optionGroup : String -> List (Html Msg) -> Html Msg
optionGroup title elements =
    Html.div [ Html.Attributes.class "flex-container", Html.Attributes.class "column" ]
        (Html.legend [] [ Html.text title ] :: elements)


viewOptions : Bool -> Maybe Float -> WaypointsOptions -> Bool -> CuesViewOptions -> Maybe String -> Maybe Location.LocationState -> Maybe Location.LocationError -> Bool -> Int -> Html Msg
viewOptions show maxDistance waypointOptions showStartFinish cuesViewOptions gpxError location locationError trackingEnabled trackingIntervalSec =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "justify-content" "center"
        , Html.Attributes.style "overflow" "auto"
        , Html.Attributes.class "narrow"
        ]
        (if not show then
            [ Html.p
                [ Html.Attributes.style "transform" "rotate(90deg)"
                , Html.Attributes.style "white-space" "nowrap"
                , Html.Attributes.style "width" "1em"
                ]
                [ Html.span [ Html.Events.onClick <| ShowOptions True ] [ Html.text "options" ]
                ]
            ]

         else
            List.concat
                [ [ Html.div [ Html.Attributes.class "options" ] <|
                        [ Html.h2 [] [ Html.text "Options" ]
                        , Html.p [ Html.Events.onClick <| ShowOptions False ] [ Html.text "(hide)" ]
                        , Html.hr [] []
                        , optionGroup "Waypoint categories"
                            (Dropdown.dropdown
                                (Dropdown.Options
                                    [ Dropdown.Item "all" "all" True
                                    , Dropdown.Item "filtered" "filtered" True
                                    ]
                                    Maybe.Nothing
                                    (Maybe.map
                                        (\selection ->
                                            case selection of
                                                "all" ->
                                                    UpdateCategoryFilterEnabled False

                                                "filtered" ->
                                                    UpdateCategoryFilterEnabled True

                                                _ ->
                                                    NoOp
                                        )
                                        >> Maybe.withDefault NoOp
                                    )
                                )
                                []
                                (Maybe.Just <|
                                    if waypointOptions.categoryFilterEnabled then
                                        "filtered"

                                    else
                                        "all"
                                )
                                :: (if waypointOptions.categoryFilterEnabled then
                                        [ Html.fieldset []
                                            ((waypointOptions.filteredCategories
                                                |> Dict.toList
                                                |> List.map
                                                    (\( typ, included ) ->
                                                        checkbox included
                                                            (CategoryEnabled typ (not included))
                                                            (if typ /= unknownCategory then
                                                                typ

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
                        , Html.hr [] []
                        , optionGroup "Start/Finish"
                            [ checkbox showStartFinish (UpdateShowStartFinish (not showStartFinish)) "Show start/finish"
                            ]
                        , Html.hr [] []
                        , optionGroup "Total distance"
                            ([ Dropdown.dropdown
                                (Dropdown.Options
                                    [ Dropdown.Item (formatTotalDistanceDisplay FromZero) (formatTotalDistanceDisplay FromZero) True
                                    , Dropdown.Item (formatTotalDistanceDisplay ToFinish) (formatTotalDistanceDisplay ToFinish) True
                                    , Dropdown.Item (formatTotalDistanceDisplay ToPoint) (formatTotalDistanceDisplay ToPoint) True
                                    , Dropdown.Item (formatTotalDistanceDisplay None) (formatTotalDistanceDisplay None) True
                                    ]
                                    Maybe.Nothing
                                    (Maybe.map parseTotalDistanceDisplay
                                        >> Maybe.withDefault Maybe.Nothing
                                        >> UpdateTotalDistanceDisplay
                                    )
                                )
                                []
                                (Maybe.Just <| formatTotalDistanceDisplay cuesViewOptions.totalDistanceDisplay)
                             ]
                                ++ (case cuesViewOptions.totalDistanceDisplay of
                                        ToPoint ->
                                            [ Html.p []
                                                [ Html.input
                                                    [ Html.Attributes.type_ "number"
                                                    , Html.Attributes.min "0"
                                                    , maxDistance |> Maybe.map (String.fromFloat >> Html.Attributes.max) |> Maybe.withDefault (Html.Attributes.disabled True)
                                                    , Html.Attributes.value <| String.fromFloat cuesViewOptions.referencePoint
                                                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1000 >> UpdateReferencePoint)
                                                    ]
                                                    []
                                                ]
                                            ]

                                        _ ->
                                            []
                                   )
                            )
                        , Html.hr [] []
                        , optionGroup "Position"
                            [ Html.input
                                [ Html.Attributes.type_ "range"
                                , Html.Attributes.min "0"
                                , maxDistance |> Maybe.map (String.fromFloat >> Html.Attributes.max) |> Maybe.withDefault (Html.Attributes.disabled True)
                                , Html.Attributes.value <| String.fromFloat cuesViewOptions.position
                                , Html.Events.onInput (String.toFloat >> Maybe.withDefault 0.0 >> UpdatePosition)
                                ]
                                []
                            ]
                        , optionGroup "Spacing"
                            [ Html.input
                                [ Html.Attributes.type_ "range"
                                , Html.Attributes.min "1"
                                , Html.Attributes.max "50"
                                , Html.Attributes.value <| String.fromInt cuesViewOptions.itemSpacing
                                , Html.Events.onInput (String.toInt >> Maybe.withDefault defaultSpacing >> UpdateItemSpacing)
                                ]
                                []
                            ]
                        , Html.hr [] []
                        , optionGroup "Distance detail"
                            [ Html.input
                                [ Html.Attributes.type_ "range"
                                , Html.Attributes.min "0"
                                , Html.Attributes.max "3"
                                , Html.Attributes.value <| String.fromInt cuesViewOptions.distanceDetail
                                , Html.Events.onInput (String.toInt >> Maybe.withDefault defaultDistanceDetail >> UpdateDistanceDetail)
                                ]
                                []
                            ]
                        , Html.hr [] []
                        , Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.style "justify-content" "center"
                            , Html.Attributes.style "align-items" "center"
                            ]
                            [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "upload GPX" OpenFileBrowser
                            , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "clear" (ShowPage <| WelcomePage False)
                            ]
                        , Html.hr [] []
                        , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "Refresh Location" RequestLocation
                        , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ]
                            (if trackingEnabled then
                                "Stop Tracking"

                             else
                                "Start Tracking"
                            )
                            ToggleTracking
                        ]
                        ++ (if trackingEnabled then
                                [ optionGroup ("Interval: " ++ String.fromInt trackingIntervalSec ++ "s")
                                    [ Html.input
                                        [ Html.Attributes.type_ "range"
                                        , Html.Attributes.min "10"
                                        , Html.Attributes.max "300"
                                        , Html.Attributes.step "10"
                                        , Html.Attributes.value <| String.fromInt trackingIntervalSec
                                        , Html.Events.onInput (String.toInt >> Maybe.withDefault 60 >> SetTrackingInterval)
                                        ]
                                        []
                                    ]
                                ]

                            else
                                []
                           )
                        ++ [ Html.p
                                [ Html.Attributes.style "font-size" "0.8em"
                                , Html.Attributes.style "margin" "0.5em 0"
                                ]
                                [ Html.text
                                    (case locationError of
                                        Just err ->
                                            Location.locationErrorToString err

                                        Nothing ->
                                            case location of
                                                Just loc ->
                                                    "Accuracy: " ++ String.fromFloat (toFloat (round (loc.accuracy * 10)) / 10) ++ "m"

                                                Nothing ->
                                                    "No location fix"
                                    )
                                ]
                           ]
                  ]
                , gpxError |> Maybe.map (\err -> [ Html.br [] [], viewGpxErrorPanel err ]) |> Maybe.withDefault [ Html.div [] [] ]
                ]
        )


viewGpxErrorPanel : String -> Html Msg
viewGpxErrorPanel error =
    viewErrorPanel <| ("There was an error processing your GPX file. Please fix any error and try again 😇\n\nError: " ++ String.left 1000 error)


viewErrorPanel : String -> Html Msg
viewErrorPanel error =
    Html.div [ Html.Attributes.class "error_panel" ] [ Html.text error ]


viewButton : String -> Msg -> Html Msg
viewButton text msg =
    viewButtonWithAttributes [] text msg


viewButtonWithAttributes : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButtonWithAttributes attrs text msg =
    Html.button
        ([ Html.Events.onClick msg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


parseTotalDistanceDisplay : String -> Maybe TotalDistanceDisplay
parseTotalDistanceDisplay v =
    case v of
        "from zero" ->
            Maybe.Just FromZero

        "to finish" ->
            Maybe.Just ToFinish

        "to point" ->
            Maybe.Just <| ToPoint

        "hide" ->
            Maybe.Just None

        _ ->
            Maybe.Nothing


formatTotalDistanceDisplay : TotalDistanceDisplay -> String
formatTotalDistanceDisplay v =
    case v of
        FromZero ->
            "from zero"

        ToFinish ->
            "to finish"

        ToPoint ->
            "to point"

        None ->
            "hide"


injectStartFinish : Float -> List GpxApi.Waypoint -> List GpxApi.Waypoint
injectStartFinish finishDistance waypoints =
    let
        hasWaypointAtDistance d =
            List.any (\w -> w.distance == d) waypoints

        withStart =
            if hasWaypointAtDistance 0 then
                waypoints

            else
                GpxApi.Waypoint 0 "Start" [ startFinishCategory ] :: waypoints
    in
    if hasWaypointAtDistance finishDistance then
        withStart

    else
        withStart ++ [ GpxApi.Waypoint finishDistance "Finish" [ startFinishCategory ] ]


cues : WaypointsOptions -> List GpxApi.Waypoint -> List GpxApi.Waypoint
cues waypointOptions waypoints =
    if waypointOptions.categoryFilterEnabled then
        List.filterMap
            (\w ->
                let
                    includeCategory =
                        \cat ->
                            Dict.get cat waypointOptions.filteredCategories
                                |> Maybe.withDefault True
                in
                case w.categories of
                    -- if no categories then we just check the unknown category key
                    [] ->
                        if includeCategory unknownCategory then
                            Maybe.Just w

                        else
                            Maybe.Nothing

                    cats ->
                        case List.filter includeCategory cats of
                            -- If there are categories and they are all filtered out, don't show waypoint
                            [] ->
                                Maybe.Nothing

                            some ->
                                Maybe.Just { w | categories = some }
            )
            waypoints

    else
        waypoints


cuesheet : List GpxApi.Waypoint -> CuesViewOptions -> Float -> Html Msg
cuesheet waypoints cuesViewOptions finishDistance =
    let
        info =
            waypointInfos cuesViewOptions.position waypoints

        svgHeight =
            (*) cuesViewOptions.itemSpacing (List.length info)

        svgContentLeftStart =
            0

        svgContentLeftStartString =
            String.fromInt svgContentLeftStart
    in
    Html.div
        [ Html.Attributes.class "cuesheet"
        ]
        [ Svg.svg
            [ Svg.Attributes.width "100%"
            , Svg.Attributes.height <| String.fromInt svgHeight
            , Svg.Attributes.viewBox <| "-40 -10 240 " ++ String.fromInt (svgHeight + cuesViewOptions.itemSpacing)
            ]
            -- TODO(glynternet): handle when no waypoints present after filtering
            (info
                |> List.indexedMap
                    (\i item ->
                        let
                            translate =
                                Svg.Attributes.transform <| "translate(0," ++ (String.fromInt <| i * cuesViewOptions.itemSpacing) ++ ")"
                        in
                        case item of
                            InfoWaypoint waypoint ->
                                let
                                    waypointDistance =
                                        case cuesViewOptions.totalDistanceDisplay of
                                            None ->
                                                Maybe.Nothing

                                            FromZero ->
                                                Maybe.Just (formatKm cuesViewOptions.distanceDetail waypoint.distance)

                                            ToFinish ->
                                                Maybe.Just (formatKm cuesViewOptions.distanceDetail (finishDistance - waypoint.distance))

                                            ToPoint ->
                                                Maybe.Just (formatKm cuesViewOptions.distanceDetail (cuesViewOptions.referencePoint - waypoint.distance))

                                    waypointInfo =
                                        List.filterMap identity
                                            [ waypointDistance
                                            , case waypoint.categories of
                                                [] ->
                                                    Maybe.Nothing

                                                cats ->
                                                    Maybe.Just <| String.join ", " cats
                                            ]

                                    waypointInfoLines =
                                        if List.isEmpty waypointInfo then
                                            [ "◉" ]

                                        else
                                            waypointInfo
                                in
                                Svg.g [ translate ]
                                    (Svg.text_
                                        [ Svg.Attributes.x (String.fromInt <| svgContentLeftStart + 10)
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.y <| String.fromInt (cuesViewOptions.itemSpacing // 2)
                                        ]
                                        [ Svg.text waypoint.name ]
                                        :: (waypointInfoLines
                                                |> List.indexedMap
                                                    (\j line ->
                                                        Svg.text_
                                                            [ Svg.Attributes.x svgContentLeftStartString
                                                            , Svg.Attributes.y <| String.fromInt (cuesViewOptions.itemSpacing // 2)
                                                            , Svg.Attributes.dominantBaseline "middle"
                                                            , Svg.Attributes.dy (String.fromFloat (toFloat j - (toFloat <| List.length waypointInfoLines - 1) / 2) ++ "em")
                                                            , Svg.Attributes.textAnchor "end"
                                                            , Svg.Attributes.fontSize "smaller"
                                                            ]
                                                            [ Svg.text line ]
                                                    )
                                           )
                                    )

                            Ride dist ->
                                let
                                    arrowTop =
                                        "2"

                                    arrowBottom =
                                        String.fromInt <| cuesViewOptions.itemSpacing - 2

                                    arrowHeadTop =
                                        String.fromInt <| cuesViewOptions.itemSpacing - 6

                                    strokeWidth =
                                        "1"
                                in
                                Svg.g [ translate ]
                                    [ Svg.line
                                        [ Svg.Attributes.x1 svgContentLeftStartString
                                        , Svg.Attributes.y1 arrowTop
                                        , Svg.Attributes.x2 svgContentLeftStartString
                                        , Svg.Attributes.y2 arrowBottom
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth strokeWidth
                                        ]
                                        []
                                    , Svg.line
                                        [ Svg.Attributes.x1 <| String.fromInt <| svgContentLeftStart - 2
                                        , Svg.Attributes.y1 <| arrowHeadTop
                                        , Svg.Attributes.x2 <| String.fromInt <| svgContentLeftStart
                                        , Svg.Attributes.y2 arrowBottom
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth strokeWidth
                                        ]
                                        []
                                    , Svg.line
                                        [ Svg.Attributes.x1 <| String.fromInt <| svgContentLeftStart + 2
                                        , Svg.Attributes.y1 <| arrowHeadTop
                                        , Svg.Attributes.x2 <| String.fromInt <| svgContentLeftStart
                                        , Svg.Attributes.y2 arrowBottom
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth strokeWidth
                                        ]
                                        []
                                    , Svg.text_
                                        [ Svg.Attributes.x (String.fromInt <| svgContentLeftStart + 10)
                                        , Svg.Attributes.y <| String.fromInt (cuesViewOptions.itemSpacing // 2)
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.fontSize "smaller"
                                        ]
                                        [ Svg.text <| formatKm cuesViewOptions.distanceDetail dist ]
                                    ]
                    )
            )
        ]


waypointInfos : Float -> List GpxApi.Waypoint -> List Info
waypointInfos position waypoints =
    List.foldl
        (\el accum ->
            if el.distance < position then
                accum

            else
                ( Maybe.Just el
                , (InfoWaypoint el
                    :: (Tuple.first accum
                            |> Maybe.map (\previous -> [ Ride (el.distance - previous.distance) ])
                            |> Maybe.withDefault []
                       )
                  )
                    ++ Tuple.second accum
                )
        )
        ( Maybe.Nothing, [] )
        waypoints
        |> Tuple.second
        |> List.reverse


formatKm : Int -> Float -> String
formatKm decimalPlaces metres =
    Round.round decimalPlaces (metres / 1000) ++ "km"


checkbox : Bool -> msg -> String -> Html msg
checkbox b msg name =
    Html.div []
        [ Html.input [ Html.Attributes.type_ "checkbox", Html.Events.onClick msg, Html.Attributes.checked b ] []
        , Html.label [ Html.Events.onClick msg ] [ Html.text name ]
        ]


defaultSpacing =
    25


defaultDistanceDetail =
    1



-- STATE
-- The field names in these encoded JSON objects must match exactly the field names
-- in the records of the Model to ensure that deserialising works as expected.


type alias StoredStateCodeFields =
    { waypoints : String
    , waypointName : String
    , waypointDistance : String
    , waypointCategories : String
    , totalDistanceDisplay : String
    , referencePoint : String
    , distanceDetail : String
    , categoryFilterEnabled : String
    , filteredCategories : String
    , itemSpacing : String
    , showOptions : String
    , showStartFinish : String

    -- When finishDistance can be inferred from trackpoints, remove finishDistance from storedState
    , finishDistance : String
    , trackingIntervalSec : String
    }


longFieldNames : StoredStateCodeFields
longFieldNames =
    { waypoints = "waypoints"
    , waypointName = "name"
    , waypointDistance = "distance"
    , waypointCategories = "categories"
    , totalDistanceDisplay = "totalDistanceDisplay"
    , referencePoint = "referencePoint"
    , distanceDetail = "distanceDetail"
    , categoryFilterEnabled = "categoryFilterEnabled"
    , filteredCategories = "filteredCategories"
    , itemSpacing = "itemSpacing"
    , showOptions = "showOptions"
    , showStartFinish = "showStartFinish"
    , finishDistance = "finishDistance"
    , trackingIntervalSec = "trackingIntervalSec"
    }


encodeSavedState : StoredStateCodeFields -> Model -> String
encodeSavedState fieldNames model =
    Json.Encode.object
        ((case model.page of
            CuesheetPage cuesModel ->
                [ ( fieldNames.waypoints, encodeWaypoints fieldNames cuesModel.waypoints )
                , ( fieldNames.categoryFilterEnabled, Json.Encode.bool cuesModel.waypointOptions.categoryFilterEnabled )
                , ( fieldNames.filteredCategories, Json.Encode.dict identity Json.Encode.bool cuesModel.waypointOptions.filteredCategories )
                , ( fieldNames.showStartFinish, Json.Encode.bool cuesModel.showStartFinish )
                , ( fieldNames.finishDistance, Json.Encode.float cuesModel.finishDistance )
                ]

            _ ->
                []
         )
            ++ [ ( fieldNames.totalDistanceDisplay, Json.Encode.string <| formatTotalDistanceDisplay model.cuesViewOptions.totalDistanceDisplay )
               , ( fieldNames.referencePoint, Json.Encode.float model.cuesViewOptions.referencePoint )
               , ( fieldNames.distanceDetail, Json.Encode.int model.cuesViewOptions.distanceDetail )
               , ( fieldNames.itemSpacing, Json.Encode.int model.cuesViewOptions.itemSpacing )
               , ( fieldNames.showOptions, Json.Encode.bool model.showOptions )
               , ( fieldNames.trackingIntervalSec, Json.Encode.int model.trackingIntervalSec )
               ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : StoredStateCodeFields -> Json.Decode.Decoder StoredState
storedStateDecoder fieldNames =
    Json.Decode.map8 StoredState
        (Json.Decode.maybe (Json.Decode.field fieldNames.waypoints (decodeWaypoints fieldNames)))
        (Json.Decode.maybe (Json.Decode.field fieldNames.totalDistanceDisplay Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field fieldNames.referencePoint Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field fieldNames.categoryFilterEnabled Json.Decode.bool))
        (Json.Decode.maybe (Json.Decode.field fieldNames.filteredCategories (Json.Decode.dict Json.Decode.bool)))
        (Json.Decode.maybe (Json.Decode.field fieldNames.itemSpacing Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field fieldNames.distanceDetail Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field fieldNames.showOptions Json.Decode.bool))
        |> andMap (Json.Decode.maybe (Json.Decode.field fieldNames.showStartFinish Json.Decode.bool))
        |> andMap (Json.Decode.maybe (Json.Decode.field fieldNames.finishDistance Json.Decode.float))
        |> andMap (Json.Decode.maybe (Json.Decode.field fieldNames.trackingIntervalSec Json.Decode.int))


andMap : Json.Decode.Decoder a -> Json.Decode.Decoder (a -> b) -> Json.Decode.Decoder b
andMap =
    Json.Decode.map2 (|>)


decodeWaypoints : StoredStateCodeFields -> Json.Decode.Decoder (List GpxApi.Waypoint)
decodeWaypoints fieldNames =
    Json.Decode.list
        (Json.Decode.map3 GpxApi.Waypoint
            (Json.Decode.field fieldNames.waypointDistance Json.Decode.float)
            (Json.Decode.field fieldNames.waypointName Json.Decode.string)
            (Json.Decode.field fieldNames.waypointCategories (Json.Decode.list Json.Decode.string))
        )


encodeWaypoints : StoredStateCodeFields -> List GpxApi.Waypoint -> Json.Encode.Value
encodeWaypoints fieldNames waypoints =
    Json.Encode.list
        (\waypoint ->
            Json.Encode.object
                [ ( fieldNames.waypointName, Json.Encode.string waypoint.name )
                , ( fieldNames.waypointDistance, Json.Encode.float waypoint.distance )
                , ( fieldNames.waypointCategories, Json.Encode.list Json.Encode.string waypoint.categories )
                ]
        )
        waypoints


port storeState : String -> Cmd msg


port calculateElevationProfileData : String -> Cmd msg


port receiveElevationProfileData : (String -> msg) -> Sub msg


port requestLocation : () -> Cmd msg


port receiveLocation : (Json.Decode.Value -> msg) -> Sub msg
