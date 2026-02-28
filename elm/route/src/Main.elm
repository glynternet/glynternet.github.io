port module Main exposing (main)

import Browser
import Browser.Navigation
import Dict
import Dropdown
import File exposing (File)
import File.Select
import GpxApi
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Json.Encode
import List.Extra
import Location
import Round
import String
import Svg
import Svg.Attributes
import Task
import Time
import Url
import Zipper exposing (Zipper)



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
        , receiveElevationProfileData WasmResponseReceived
        ]



-- MODEL


type alias Model =
    { tracks : LoadableResource (Zipper GpxApi.Track)
    , showOptions : Bool
    , activeTab : Tab

    -- Location tracking
    , location : Maybe LocationState
    , locationError : Maybe LocationError
    , trackingEnabled : Bool
    , trackingIntervalSec : Int

    -- Category filtering
    , categoryFilterEnabled : Bool
    , filteredCategories : Dict.Dict String Bool

    -- View-specific options
    , elevationProfile : ElevationProfileOptions
    , cuesheet : CuesheetOptions
    }


type Tab
    = ElevationProfileTab
    | CuesheetTab
    | WaypointsTab


type alias ElevationProfileOptions =
    { fontSize : Float
    , trackHeight : Int
    , trackThickness : Float
    , waypointStrokeColor : String
    , showIntensity : Bool
    , intensityTau : Float
    , manualPosition : Maybe Float
    , splits : Int
    }


type alias CuesheetOptions =
    { totalDistanceDisplay : TotalDistanceDisplay
    , referencePoint : Float
    , position : Float
    , itemSpacing : Int
    , distanceDetail : Int
    , showStartFinish : Bool
    }


type TotalDistanceDisplay
    = FromZero
    | ToFinish
    | ToPoint
    | ToWaypoint Int
    | FromWaypoint Int
    | None


type alias Track =
    GpxApi.Track


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


defaultElevationProfileOptions : ElevationProfileOptions
defaultElevationProfileOptions =
    { fontSize = 15
    , trackHeight = 200
    , trackThickness = 1
    , waypointStrokeColor = "lightgray"
    , showIntensity = False
    , intensityTau = 500
    , manualPosition = Nothing
    , splits = 1
    }


defaultCuesheetOptions : CuesheetOptions
defaultCuesheetOptions =
    { totalDistanceDisplay = FromZero
    , referencePoint = 1000
    , position = 0
    , itemSpacing = defaultSpacing
    , distanceDetail = defaultDistanceDetail
    , showStartFinish = False
    }


defaultSpacing : Int
defaultSpacing =
    25


defaultDistanceDetail : Int
defaultDistanceDetail =
    1



-- STORED STATE


type alias StoredState =
    { tracks : Maybe (Zipper GpxApi.Track)
    , activeTab : Maybe String
    , showOptions : Maybe Bool
    , trackingIntervalSec : Maybe Int
    , categoryFilterEnabled : Maybe Bool
    , filteredCategories : Maybe (Dict.Dict String Bool)

    -- Elevation profile
    , fontSize : Maybe Float
    , trackHeight : Maybe Int
    , trackThickness : Maybe Float
    , waypointStrokeColor : Maybe String
    , showIntensity : Maybe Bool
    , intensityTau : Maybe Float
    , manualPosition : Maybe Float
    , splits : Maybe Int

    -- Cuesheet
    , totalDistanceDisplay : Maybe String
    , referencePoint : Maybe Float
    , itemSpacing : Maybe Int
    , distanceDetail : Maybe Int
    , showStartFinish : Maybe Bool
    }


storedStateModel : StoredState -> Model
storedStateModel state =
    { tracks = loadableResourceFromMaybe state.tracks
    , showOptions = state.showOptions |> Maybe.withDefault True
    , activeTab = state.activeTab |> Maybe.andThen parseTab |> Maybe.withDefault ElevationProfileTab
    , location = Nothing
    , locationError = Nothing
    , trackingEnabled = False
    , trackingIntervalSec = state.trackingIntervalSec |> Maybe.withDefault 60
    , categoryFilterEnabled = state.categoryFilterEnabled |> Maybe.withDefault False
    , filteredCategories = state.filteredCategories |> Maybe.withDefault Dict.empty
    , elevationProfile =
        { fontSize = state.fontSize |> Maybe.withDefault defaultElevationProfileOptions.fontSize
        , trackHeight = state.trackHeight |> Maybe.withDefault defaultElevationProfileOptions.trackHeight
        , trackThickness = state.trackThickness |> Maybe.withDefault defaultElevationProfileOptions.trackThickness
        , waypointStrokeColor = state.waypointStrokeColor |> Maybe.withDefault defaultElevationProfileOptions.waypointStrokeColor
        , showIntensity = state.showIntensity |> Maybe.withDefault defaultElevationProfileOptions.showIntensity
        , intensityTau = state.intensityTau |> Maybe.withDefault defaultElevationProfileOptions.intensityTau
        , manualPosition = state.manualPosition
        , splits = state.splits |> Maybe.withDefault defaultElevationProfileOptions.splits
        }
    , cuesheet =
        { totalDistanceDisplay = state.totalDistanceDisplay |> Maybe.andThen parseTotalDistanceDisplay |> Maybe.withDefault defaultCuesheetOptions.totalDistanceDisplay
        , referencePoint = state.referencePoint |> Maybe.withDefault defaultCuesheetOptions.referencePoint
        , position = 0
        , itemSpacing = state.itemSpacing |> Maybe.withDefault defaultCuesheetOptions.itemSpacing
        , distanceDetail = state.distanceDetail |> Maybe.withDefault defaultCuesheetOptions.distanceDetail
        , showStartFinish = state.showStartFinish |> Maybe.withDefault defaultCuesheetOptions.showStartFinish
        }
    }


defaultStoredState : StoredState
defaultStoredState =
    StoredState Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState
        |> Maybe.map
            (Json.Decode.decodeValue storedStateDecoder
                >> Result.withDefault defaultStoredState
                >> storedStateModel
            )
        |> Maybe.withDefault (storedStateModel defaultStoredState)
    , Cmd.none
    )



-- MSG


type Msg
    = Ignore
      -- Shared
    | ShowOptions Bool
    | OpenFileBrowser
    | FileUploaded File.File
    | GPXStringed String
    | WasmResponseReceived String
    | NavigateToPrevious
    | NavigateToNext
    | SwitchTab Tab
      -- Location
    | LocationReceived Json.Decode.Value
    | RequestLocation
    | ToggleTracking
    | SetTrackingInterval Int
    | Tick Time.Posix
      -- Category filtering
    | CategoryEnabled String Bool
    | UpdateCategoryFilterEnabled Bool
    | SetAllCategoriesEnabled Bool
      -- Waypoint editing
    | WaypointDistanceChange Int Float
    | WaypointNameChange Int String
    | DeleteWaypoint Int
      -- Elevation profile
    | UpdateFontSize Float
    | UpdateTrackHeight Int
    | UpdateTrackThickness Float
    | WaypointStrokeColourChange String
    | ShowIntensity Bool
    | UpdateIntensityTau Float
    | UpdateManualPosition (Maybe Float)
    | UpdateSplits Int
      -- Cuesheet
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdatePosition Float
    | UpdateReferencePoint Float
    | UpdateItemSpacing Int
    | UpdateDistanceDetail Int
    | UpdateShowStartFinish Bool
    | UpdateSelectedWaypoint Int



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Ignore ->
            ( model, Cmd.none )

        ShowOptions show ->
            ( { model | showOptions = show }, Cmd.none )

        SwitchTab tab ->
            updateModel { model | activeTab = tab }

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

        GPXStringed gpxContent ->
            ( model, calculateElevationProfileData gpxContent )

        WasmResponseReceived string ->
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
                                        case Zipper.fromList tracks of
                                            Nothing ->
                                                Error "No tracks available in uploaded GPX"

                                            Just positionalTracks ->
                                                Loaded positionalTracks
                                    , filteredCategories = categories
                                }

        NavigateToPrevious ->
            case model.tracks of
                Loaded tracks ->
                    updateModel { model | tracks = Loaded (Zipper.navigatePrevious tracks) }

                _ ->
                    ( model, Cmd.none )

        NavigateToNext ->
            case model.tracks of
                Loaded tracks ->
                    updateModel { model | tracks = Loaded (Zipper.navigateNext tracks) }

                _ ->
                    ( model, Cmd.none )

        -- Location
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
            case Json.Decode.decodeValue Location.decodeLocationResult value of
                Ok (Ok pos) ->
                    case model.tracks of
                        Loaded tracks ->
                            let
                                gpsPos =
                                    Location.LatLon pos.lat pos.lon

                                matchedDist =
                                    Location.findNearestTrackPoint gpsPos tracks.current.trackpoints
                                        |> Maybe.map .distance
                                        |> Maybe.withDefault 0

                                cs =
                                    model.cuesheet
                            in
                            ( { model
                                | location = Just (Location.LocationState gpsPos pos.accuracy matchedDist)
                                , locationError = Nothing
                                , cuesheet = { cs | position = matchedDist }
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

        -- Category filtering
        CategoryEnabled category enabled ->
            let
                newCategories =
                    Dict.insert category enabled model.filteredCategories
            in
            updateModel (correctWaypointSelectionInModel { model | filteredCategories = newCategories })

        UpdateCategoryFilterEnabled enabled ->
            updateModel (correctWaypointSelectionInModel { model | categoryFilterEnabled = enabled })

        SetAllCategoriesEnabled enabled ->
            updateModel (correctWaypointSelectionInModel { model | filteredCategories = Dict.map (\_ _ -> enabled) model.filteredCategories })

        -- Waypoint editing
        WaypointNameChange i name ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model
                            | tracks =
                                Loaded <|
                                    Zipper.updateCurrent
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
                                    Zipper.updateCurrent
                                        (\current -> trackUpdateWaypoint current i (\w -> { w | distance = dist }))
                                        tracks
                        }

                _ ->
                    ( model, Cmd.none )

        DeleteWaypoint i ->
            case model.tracks of
                Loaded tracks ->
                    updateModel
                        { model
                            | tracks =
                                Loaded <|
                                    Zipper.updateCurrent
                                        (\current -> trackWithWaypoints current (List.Extra.removeAt i current.waypoints))
                                        tracks
                        }

                _ ->
                    ( model, Cmd.none )

        -- Elevation profile options
        UpdateFontSize size ->
            let
                ep =
                    model.elevationProfile
            in
            updateModel { model | elevationProfile = { ep | fontSize = size } }

        UpdateTrackHeight height ->
            let
                ep =
                    model.elevationProfile
            in
            updateModel { model | elevationProfile = { ep | trackHeight = height } }

        UpdateTrackThickness thickness ->
            let
                ep =
                    model.elevationProfile
            in
            updateModel { model | elevationProfile = { ep | trackThickness = thickness } }

        WaypointStrokeColourChange colour ->
            let
                ep =
                    model.elevationProfile
            in
            updateModel { model | elevationProfile = { ep | waypointStrokeColor = colour } }

        ShowIntensity show ->
            let
                ep =
                    model.elevationProfile
            in
            updateModel { model | elevationProfile = { ep | showIntensity = show } }

        UpdateIntensityTau tau ->
            let
                ep =
                    model.elevationProfile
            in
            updateModel { model | elevationProfile = { ep | intensityTau = tau } }

        UpdateManualPosition pos ->
            let
                ep =
                    model.elevationProfile
            in
            updateModel { model | elevationProfile = { ep | manualPosition = pos } }

        UpdateSplits n ->
            let
                ep =
                    model.elevationProfile
            in
            updateModel { model | elevationProfile = { ep | splits = n } }

        -- Cuesheet options
        UpdateTotalDistanceDisplay maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\selection ->
                        let
                            cs =
                                model.cuesheet
                        in
                        updateModel { model | cuesheet = { cs | totalDistanceDisplay = selection } }
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdatePosition position ->
            let
                cs =
                    model.cuesheet
            in
            updateModel { model | cuesheet = { cs | position = position } }

        UpdateReferencePoint point ->
            let
                cs =
                    model.cuesheet
            in
            updateModel { model | cuesheet = { cs | referencePoint = point } }

        UpdateItemSpacing spacing ->
            let
                cs =
                    model.cuesheet
            in
            updateModel { model | cuesheet = { cs | itemSpacing = spacing } }

        UpdateDistanceDetail detail ->
            let
                cs =
                    model.cuesheet
            in
            updateModel { model | cuesheet = { cs | distanceDetail = detail } }

        UpdateShowStartFinish show ->
            let
                cs =
                    model.cuesheet
            in
            updateModel { model | cuesheet = { cs | showStartFinish = show } }

        UpdateSelectedWaypoint idx ->
            let
                cs =
                    model.cuesheet

                newDisplay =
                    case cs.totalDistanceDisplay of
                        ToWaypoint _ ->
                            ToWaypoint idx

                        FromWaypoint _ ->
                            FromWaypoint idx

                        other ->
                            other
            in
            updateModel { model | cuesheet = { cs | totalDistanceDisplay = newDisplay } }


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    ( model, storeState (encodeSavedState model) )



-- HELPERS


trackWithWaypoints : Track -> List Waypoint -> Track
trackWithWaypoints track waypoints =
    { track | waypoints = waypoints }


trackUpdateWaypoint : Track -> Int -> (Waypoint -> Waypoint) -> Track
trackUpdateWaypoint track i updateWaypoint =
    trackWithWaypoints track <| List.Extra.updateAt i updateWaypoint track.waypoints


splitTrackByDistance : Int -> Track -> List Track
splitTrackByDistance n track =
    if n <= 1 then
        [ track ]

    else
        let
            totalDistance =
                List.reverse track.trackpoints
                    |> List.head
                    |> Maybe.map .distance
                    |> Maybe.withDefault 0

            segmentLength =
                totalDistance / toFloat n
        in
        List.range 0 (n - 1)
            |> List.map
                (\i ->
                    let
                        segStart =
                            toFloat i * segmentLength

                        segEnd =
                            toFloat (i + 1) * segmentLength

                        segTrackpoints =
                            extractSegmentTrackpoints segStart segEnd track.trackpoints

                        segWaypoints =
                            track.waypoints
                                |> List.filter (\w -> w.distance >= segStart && w.distance <= segEnd)
                                |> List.map (\w -> { w | distance = w.distance - segStart })
                    in
                    { trackpoints = segTrackpoints |> List.map (\tp -> { tp | distance = tp.distance - segStart })
                    , waypoints = segWaypoints
                    , gainLoss = computeGainLoss segTrackpoints
                    }
                )


extractSegmentTrackpoints : Float -> Float -> List TrackPoint -> List TrackPoint
extractSegmentTrackpoints segStart segEnd trackpoints =
    let
        pointsInRange =
            trackpoints
                |> List.filter (\tp -> tp.distance >= segStart && tp.distance <= segEnd)

        startPoint =
            interpolateTrackpointAt segStart trackpoints

        endPoint =
            interpolateTrackpointAt segEnd trackpoints

        withStart =
            case ( startPoint, List.head pointsInRange ) of
                ( Just sp, Just first ) ->
                    if first.distance > segStart then
                        sp :: pointsInRange

                    else
                        pointsInRange

                ( Just sp, Nothing ) ->
                    [ sp ]

                _ ->
                    pointsInRange

        withStartAndEnd =
            case ( endPoint, List.reverse withStart |> List.head ) of
                ( Just ep, Just lastPt ) ->
                    if lastPt.distance < segEnd then
                        withStart ++ [ ep ]

                    else
                        withStart

                ( Just ep, Nothing ) ->
                    [ ep ]

                _ ->
                    withStart
    in
    withStartAndEnd


computeGainLoss : List TrackPoint -> ( Float, Float )
computeGainLoss trackpoints =
    case trackpoints of
        [] ->
            ( 0, 0 )

        first :: rest ->
            computeGainLossHelper first.elevation ( 0, 0 ) rest


computeGainLossHelper : Float -> ( Float, Float ) -> List TrackPoint -> ( Float, Float )
computeGainLossHelper prevEle ( gain, loss ) remaining =
    case remaining of
        [] ->
            ( gain, loss )

        tp :: rest ->
            let
                delta =
                    tp.elevation - prevEle
            in
            if delta > 0 then
                computeGainLossHelper tp.elevation ( gain + delta, loss ) rest

            else
                computeGainLossHelper tp.elevation ( gain, loss - delta ) rest


interpolateTrackpointAt : Float -> List TrackPoint -> Maybe TrackPoint
interpolateTrackpointAt dist trackpoints =
    case trackpoints of
        [] ->
            Nothing

        [ only ] ->
            if only.distance == dist then
                Just only

            else
                Nothing

        a :: b :: rest ->
            if a.distance == dist then
                Just a

            else if a.distance < dist && b.distance >= dist then
                let
                    t =
                        if b.distance == a.distance then
                            0

                        else
                            (dist - a.distance) / (b.distance - a.distance)
                in
                Just
                    { distance = dist
                    , elevation = a.elevation + t * (b.elevation - a.elevation)
                    , lat = a.lat + t * (b.lat - a.lat)
                    , lon = a.lon + t * (b.lon - a.lon)
                    }

            else
                interpolateTrackpointAt dist (b :: rest)


unknownCategory : String
unknownCategory =
    ""


startFinishCategory : String
startFinishCategory =
    "Start/Finish"


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


indexedFilteredWaypoints : List Waypoint -> List Waypoint -> List ( Int, Waypoint )
indexedFilteredWaypoints allWaypoints filtered =
    allWaypoints
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, wp ) -> List.member wp filtered)


correctWaypointSelection : TotalDistanceDisplay -> List ( Int, Waypoint ) -> TotalDistanceDisplay
correctWaypointSelection display indexed =
    case display of
        ToWaypoint idx ->
            if List.any (\( i, _ ) -> i == idx) indexed then
                display

            else
                case List.Extra.last indexed of
                    Just ( lastIdx, _ ) ->
                        ToWaypoint lastIdx

                    Nothing ->
                        display

        FromWaypoint idx ->
            if List.any (\( i, _ ) -> i == idx) indexed then
                display

            else
                case List.head indexed of
                    Just ( firstIdx, _ ) ->
                        FromWaypoint firstIdx

                    Nothing ->
                        display

        _ ->
            display


lookupWaypointByIndex : Int -> List Waypoint -> Maybe Waypoint
lookupWaypointByIndex idx waypoints =
    List.Extra.getAt idx waypoints


correctWaypointSelectionInModel : Model -> Model
correctWaypointSelectionInModel model =
    case maybeFromloadableResource model.tracks of
        Nothing ->
            model

        Just tracks ->
            let
                allWaypoints =
                    tracks.current.waypoints

                filtered =
                    filterWaypointsByCategory model.categoryFilterEnabled model.filteredCategories allWaypoints

                indexed =
                    indexedFilteredWaypoints allWaypoints filtered

                cs =
                    model.cuesheet

                corrected =
                    correctWaypointSelection cs.totalDistanceDisplay indexed
            in
            { model | cuesheet = { cs | totalDistanceDisplay = corrected } }


cuesFilterByCategory : Dict.Dict String Bool -> List Waypoint -> List Waypoint
cuesFilterByCategory filteredCategories waypoints =
    List.filterMap
        (\w ->
            let
                includeCategory cat =
                    Dict.get cat filteredCategories |> Maybe.withDefault True
            in
            case w.categories of
                [] ->
                    if includeCategory unknownCategory then
                        Just w

                    else
                        Nothing

                cats ->
                    case List.filter includeCategory cats of
                        [] ->
                            Nothing

                        some ->
                            Just { w | categories = some }
        )
        waypoints


effectivePosition : Model -> Maybe Float
effectivePosition model =
    case model.elevationProfile.manualPosition of
        Just _ ->
            model.elevationProfile.manualPosition

        Nothing ->
            model.location |> Maybe.map .matchedDistance


getFinishDistance : Zipper GpxApi.Track -> Float
getFinishDistance tracks =
    List.reverse tracks.current.trackpoints
        |> List.head
        |> Maybe.map .distance
        |> Maybe.withDefault 0


injectStartFinish : Float -> ( Float, Float ) -> List Waypoint -> List Waypoint
injectStartFinish finishDist ( totalGain, totalLoss ) waypoints =
    let
        hasWaypointAtDistance d =
            List.any (\w -> w.distance == d) waypoints

        withStart =
            if hasWaypointAtDistance 0 then
                waypoints

            else
                GpxApi.Waypoint 0 "Start" [ startFinishCategory ] 0 0 :: waypoints
    in
    if hasWaypointAtDistance finishDist then
        withStart

    else
        withStart ++ [ GpxApi.Waypoint finishDist "Finish" [ startFinishCategory ] totalGain totalLoss ]



-- VIEW


view : Model -> Browser.Document Msg
view model =
    Browser.Document "Route"
        [ Html.div
            [ Html.Attributes.class "flex-container"
            , Html.Attributes.class "row"
            , Html.Attributes.class "page"
            , Html.Attributes.style "height" "100%"
            ]
            (case model.tracks of
                NotLoaded ->
                    [ viewOptionsPanel model
                    , Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "column"
                        , Html.Attributes.class "wide"
                        , Html.Attributes.style "height" "100%"
                        , Html.Attributes.style "overflow" "auto"
                        ]
                        [ viewLandingPage ]
                    ]

                Loading ->
                    [ viewOptionsPanel model
                    , Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "column"
                        , Html.Attributes.class "wide"
                        , Html.Attributes.style "height" "100%"
                        , Html.Attributes.style "overflow" "auto"
                        ]
                        [ Html.p [] [ Html.text "Loading..." ] ]
                    ]

                Error err ->
                    [ viewOptionsPanel model
                    , Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "column"
                        , Html.Attributes.class "wide"
                        , Html.Attributes.style "height" "100%"
                        , Html.Attributes.style "overflow" "auto"
                        ]
                        [ viewErrorPanel <|
                            ("There was an error processing your file. Please fix any error and try again.\n\nError: "
                                ++ (if String.length err > 1000 then
                                        String.left 500 err ++ "...\n\n..." ++ String.right 500 err

                                    else
                                        err
                                   )
                            )
                        ]
                    ]

                Loaded tracks ->
                    [ viewOptionsPanel model
                    , Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "column"
                        , Html.Attributes.class "wide"
                        , Html.Attributes.style "height" "100%"
                        , Html.Attributes.style "overflow" "auto"
                        ]
                        [ viewTabBar model.activeTab
                        , viewTrackNavigation tracks
                        , case model.activeTab of
                            ElevationProfileTab ->
                                viewElevationProfileTab model tracks

                            CuesheetTab ->
                                viewCuesheetTab model tracks

                            WaypointsTab ->
                                viewWaypointsTab model tracks
                        ]
                    ]
            )
        ]


viewLandingPage : Html Msg
viewLandingPage =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "flex-center"
        , Html.Attributes.class "column"
        ]
        [ Html.h2 [] [ Html.text "Route tools" ]
        , Html.br [] []
        , viewButton "Upload GPX" OpenFileBrowser
        , Html.br [] []
        , Html.h3 [] [ Html.text "Features" ]
        , Html.br [] []
        , Html.ul []
            [ Html.li [] [ Html.text "Elevation profile visualization" ]
            , Html.li [] [ Html.text "Cuesheet with customizable distance display" ]
            , Html.li [] [ Html.text "GPS location tracking" ]
            , Html.li [] [ Html.text "Waypoint category filtering" ]
            , Html.li [] [ Html.text "Inline waypoint editing" ]
            , Html.li [] [ Html.text "Multi-track GPX support" ]
            ]
        ]


viewTabBar : Tab -> Html Msg
viewTabBar activeTab =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.style "justify-content" "center"
        , Html.Attributes.style "gap" "0"
        , Html.Attributes.style "padding" "0.5em"
        ]
        [ Html.button
            [ Html.Events.onClick (SwitchTab ElevationProfileTab)
            , Html.Attributes.class "button-4"
            , Html.Attributes.style "border-radius" "4px 0 0 4px"
            , if activeTab == ElevationProfileTab then
                Html.Attributes.style "font-weight" "bold"

              else
                Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text "Elevation Profile" ]
        , Html.button
            [ Html.Events.onClick (SwitchTab CuesheetTab)
            , Html.Attributes.class "button-4"
            , Html.Attributes.style "border-radius" "0"
            , if activeTab == CuesheetTab then
                Html.Attributes.style "font-weight" "bold"

              else
                Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text "Cuesheet" ]
        , Html.button
            [ Html.Events.onClick (SwitchTab WaypointsTab)
            , Html.Attributes.class "button-4"
            , Html.Attributes.style "border-radius" "0 4px 4px 0"
            , if activeTab == WaypointsTab then
                Html.Attributes.style "font-weight" "bold"

              else
                Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text "Waypoints" ]
        ]


viewTrackNavigation : Zipper GpxApi.Track -> Html Msg
viewTrackNavigation tracks =
    let
        hasPrev =
            not (List.isEmpty tracks.prev)

        hasNext =
            not (List.isEmpty tracks.next)
    in
    if not hasPrev && not hasNext then
        Html.text ""

    else
        Html.div
            [ Html.Attributes.class "flex-container"
            , Html.Attributes.style "justify-content" "center"
            , Html.Attributes.style "gap" "1em"
            , Html.Attributes.style "padding" "0.5em"
            ]
            [ if hasPrev then
                Html.button [ Html.Events.onClick NavigateToPrevious ] [ Html.text "← Prev track" ]

              else
                Html.text ""
            , Html.text ("Track " ++ String.fromInt (List.length tracks.prev + 1) ++ " of " ++ String.fromInt (List.length tracks.prev + 1 + List.length tracks.next))
            , if hasNext then
                Html.button [ Html.Events.onClick NavigateToNext ] [ Html.text "Next track →" ]

              else
                Html.text ""
            ]



-- ELEVATION PROFILE VIEW


viewElevationProfileTab : Model -> Zipper GpxApi.Track -> Html Msg
viewElevationProfileTab model tracks =
    let
        ep =
            model.elevationProfile

        maxDistance =
            Maybe.withDefault 1 <| List.maximum <| List.map .distance tracks.current.trackpoints

        trackMaxElevation =
            Maybe.withDefault 1 <| List.maximum <| List.map .elevation tracks.current.trackpoints

        trackMinElevation =
            Maybe.withDefault 1 <| List.minimum <| List.map .elevation tracks.current.trackpoints

        filteredWaypoints =
            filterWaypointsByCategory model.categoryFilterEnabled model.filteredCategories tracks.current.waypoints

        pos =
            effectivePosition model

        segmentLength =
            maxDistance / toFloat (max 1 ep.splits)

        fullIntensity =
            if ep.showIntensity then
                computeIntensity ep.intensityTau tracks.current.trackpoints

            else
                []

        profileViews =
            GpxApi.Track tracks.current.trackpoints filteredWaypoints tracks.current.gainLoss
                |> splitTrackByDistance ep.splits
                |> List.indexedMap
                    (\i seg ->
                        let
                            segMaxDistance =
                                List.reverse seg.trackpoints
                                    |> List.head
                                    |> Maybe.map .distance
                                    |> Maybe.withDefault segmentLength

                            segStart =
                                toFloat i * segmentLength

                            segEnd =
                                segStart + segmentLength

                            segPosition =
                                pos
                                    |> Maybe.andThen
                                        (\p ->
                                            if p >= segStart && p <= segEnd then
                                                Just (p - segStart)

                                            else
                                                Nothing
                                        )

                            segIntensity =
                                fullIntensity
                                    |> List.filter (\pt -> pt.distance >= segStart && pt.distance <= segEnd)
                                    |> List.map (\pt -> { pt | distance = pt.distance - segStart })
                        in
                        profile seg segMaxDistance trackMinElevation trackMaxElevation ep.fontSize ep.trackHeight ep.trackThickness ep.waypointStrokeColor segPosition segIntensity
                    )
    in
    Html.div [] profileViews


profile : Track -> Float -> Float -> Float -> Float -> Int -> Float -> String -> Maybe Float -> List { distance : Float, intensity : Float } -> Html Msg
profile track maxDistance minElevation maxElevation fontSize trackHeight trackThickness waypointStrokeColor maybePosition intensityPoints =
    let
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
        [ Html.Attributes.style "margin-top" "16px"
        ]
        [ let
            ( gain, loss ) =
                track.gainLoss
          in
          Html.div
            [ Html.Attributes.style "text-align" "center"
            , Html.Attributes.style "font-size" "1em"
            , Html.Attributes.style "padding" "4px 0"
            ]
            [ Html.text <| formatKm 1 maxDistance ++ " " ++ formatEleGainLoss gain loss ]
        , Svg.svg
            [ Svg.Attributes.viewBox <| "-5 -5 " ++ String.fromInt (svgWidth + 10) ++ " " ++ (String.fromInt <| svgHeight + 10)
            ]
            [ -- intensity shading
              if List.isEmpty intensityPoints then
                Svg.g [] []

              else
                renderIntensityShading (toFloat svgWidth) maxDistance (toFloat trackHeight) intensityPoints
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

                                grade =
                                    if deltaD > 0 then
                                        (current.elevation - prev.elevation) / deltaD

                                    else
                                        0

                                climbingGrade =
                                    max 0 grade

                                decay =
                                    e ^ (-deltaD / tau)

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


renderIntensityShading : Float -> Float -> Float -> List { distance : Float, intensity : Float } -> Svg.Svg msg
renderIntensityShading svgWidth maxDistance trackHeightFloat intensityPoints =
    let
        intensities =
            List.map .intensity intensityPoints

        minIntensity =
            List.minimum intensities |> Maybe.withDefault 0

        maxIntensity =
            List.maximum intensities |> Maybe.withDefault 0

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


intensityColor : Float -> String
intensityColor t =
    let
        clamped =
            clamp 0 1 t

        r =
            round
                (if clamped < 0.5 then
                    255 * clamped * 2

                 else
                    255
                )

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



-- CUESHEET VIEW


type Info
    = InfoWaypoint Waypoint
    | Ride Float ( Float, Float )


viewCuesheetTab : Model -> Zipper GpxApi.Track -> Html Msg
viewCuesheetTab model tracks =
    let
        cs =
            model.cuesheet

        currentFinishDistance =
            getFinishDistance tracks

        waypointsWithStartFinish =
            if cs.showStartFinish then
                injectStartFinish currentFinishDistance tracks.current.gainLoss tracks.current.waypoints

            else
                tracks.current.waypoints

        filteredWaypoints =
            if model.categoryFilterEnabled then
                cuesFilterByCategory model.filteredCategories waypointsWithStartFinish

            else
                waypointsWithStartFinish

        refWaypoint =
            case cs.totalDistanceDisplay of
                ToWaypoint idx ->
                    lookupWaypointByIndex idx tracks.current.waypoints

                FromWaypoint idx ->
                    lookupWaypointByIndex idx tracks.current.waypoints

                _ ->
                    Nothing

        refPointEle =
            case refWaypoint of
                Just wp ->
                    ( wp.gain, wp.loss )

                Nothing ->
                    cumulativeGainLossAtDistance cs.referencePoint tracks.current.trackpoints
    in
    Html.div []
        [ cuesheetSvg filteredWaypoints cs currentFinishDistance refPointEle refWaypoint
        ]


viewWaypointsTab : Model -> Zipper GpxApi.Track -> Html Msg
viewWaypointsTab _ tracks =
    let
        maxDistance =
            getFinishDistance tracks
    in
    Html.div []
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


cuesheetSvg : List Waypoint -> CuesheetOptions -> Float -> ( Float, Float ) -> Maybe Waypoint -> Html Msg
cuesheetSvg waypoints cs finishDist refPointEle refWaypoint =
    let
        info =
            waypointInfos cs.position waypoints

        lastWaypoint =
            List.reverse waypoints |> List.head

        svgHeight =
            (*) cs.itemSpacing (List.length info)

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
            , Svg.Attributes.viewBox <| "-40 -10 240 " ++ String.fromInt (svgHeight + cs.itemSpacing)
            ]
            (info
                |> List.indexedMap
                    (\i item ->
                        let
                            translate =
                                Svg.Attributes.transform <| "translate(0," ++ (String.fromInt <| i * cs.itemSpacing) ++ ")"
                        in
                        case item of
                            InfoWaypoint waypoint ->
                                let
                                    waypointDistance =
                                        case cs.totalDistanceDisplay of
                                            None ->
                                                Nothing

                                            FromZero ->
                                                Just (formatKm cs.distanceDetail waypoint.distance)

                                            ToFinish ->
                                                Just (formatKm cs.distanceDetail (finishDist - waypoint.distance))

                                            ToPoint ->
                                                Just (formatKm cs.distanceDetail (cs.referencePoint - waypoint.distance))

                                            ToWaypoint _ ->
                                                refWaypoint
                                                    |> Maybe.map (\rw -> formatKm cs.distanceDetail (rw.distance - waypoint.distance))

                                            FromWaypoint _ ->
                                                refWaypoint
                                                    |> Maybe.map (\rw -> formatKm cs.distanceDetail (waypoint.distance - rw.distance))

                                    waypointEle =
                                        case cs.totalDistanceDisplay of
                                            None ->
                                                Nothing

                                            FromZero ->
                                                Just (formatEleGainLoss waypoint.gain waypoint.loss)

                                            ToFinish ->
                                                lastWaypoint
                                                    |> Maybe.map
                                                        (\last ->
                                                            formatEleGainLoss
                                                                (last.gain - waypoint.gain)
                                                                (last.loss - waypoint.loss)
                                                        )

                                            ToPoint ->
                                                Just
                                                    (formatEleGainLoss
                                                        (Tuple.first refPointEle - waypoint.gain)
                                                        (Tuple.second refPointEle - waypoint.loss)
                                                    )

                                            ToWaypoint _ ->
                                                refWaypoint
                                                    |> Maybe.map
                                                        (\rw ->
                                                            formatEleGainLoss
                                                                (rw.gain - waypoint.gain)
                                                                (rw.loss - waypoint.loss)
                                                        )

                                            FromWaypoint _ ->
                                                refWaypoint
                                                    |> Maybe.map
                                                        (\rw ->
                                                            formatEleGainLoss
                                                                (waypoint.gain - rw.gain)
                                                                (waypoint.loss - rw.loss)
                                                        )

                                    waypointInfo =
                                        List.filterMap identity
                                            [ waypointDistance
                                            , waypointEle
                                            , case waypoint.categories of
                                                [] ->
                                                    Nothing

                                                cats ->
                                                    Just <| String.join ", " cats
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
                                        , Svg.Attributes.y <| String.fromInt (cs.itemSpacing // 2)
                                        ]
                                        [ Svg.text waypoint.name ]
                                        :: (waypointInfoLines
                                                |> List.indexedMap
                                                    (\j line ->
                                                        Svg.text_
                                                            [ Svg.Attributes.x svgContentLeftStartString
                                                            , Svg.Attributes.y <| String.fromInt (cs.itemSpacing // 2)
                                                            , Svg.Attributes.dominantBaseline "middle"
                                                            , Svg.Attributes.dy (String.fromFloat (toFloat j - (toFloat <| List.length waypointInfoLines - 1) / 2) ++ "em")
                                                            , Svg.Attributes.textAnchor "end"
                                                            , Svg.Attributes.fontSize "smaller"
                                                            ]
                                                            [ Svg.text line ]
                                                    )
                                           )
                                    )

                            Ride dist ( gain, loss ) ->
                                let
                                    arrowTop =
                                        "2"

                                    arrowBottom =
                                        String.fromInt <| cs.itemSpacing - 2

                                    arrowHeadTop =
                                        String.fromInt <| cs.itemSpacing - 6

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
                                        , Svg.Attributes.y <| String.fromInt (cs.itemSpacing // 2)
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.fontSize "smaller"
                                        ]
                                        [ Svg.text <|
                                            formatKm cs.distanceDetail dist
                                                ++ " "
                                                ++ formatEleGainLoss gain loss
                                        ]
                                    ]
                    )
            )
        ]


waypointInfos : Float -> List Waypoint -> List Info
waypointInfos position waypoints =
    List.foldl
        (\el accum ->
            if el.distance < position then
                accum

            else
                ( Just el
                , (InfoWaypoint el
                    :: (Tuple.first accum
                            |> Maybe.map
                                (\previous ->
                                    [ Ride (el.distance - previous.distance)
                                        ( el.gain - previous.gain
                                        , el.loss - previous.loss
                                        )
                                    ]
                                )
                            |> Maybe.withDefault []
                       )
                  )
                    ++ Tuple.second accum
                )
        )
        ( Nothing, [] )
        waypoints
        |> Tuple.second
        |> List.reverse


formatKm : Int -> Float -> String
formatKm decimalPlaces metres =
    Round.round decimalPlaces (metres / 1000) ++ "km"


formatM : Float -> String
formatM metres =
    Round.round 0 metres ++ "m"


formatEleGainLoss : Float -> Float -> String
formatEleGainLoss gain loss =
    "↑" ++ formatM gain ++ " ↓" ++ formatM loss


cumulativeGainLossAtDistance : Float -> List GpxApi.TrackPoint -> ( Float, Float )
cumulativeGainLossAtDistance dist trackpoints =
    case trackpoints of
        [] ->
            ( 0, 0 )

        first :: rest ->
            cumulativeGainLossHelper dist first.elevation ( 0, 0 ) rest


cumulativeGainLossHelper : Float -> Float -> ( Float, Float ) -> List GpxApi.TrackPoint -> ( Float, Float )
cumulativeGainLossHelper dist prevEle ( gain, loss ) remaining =
    case remaining of
        [] ->
            ( gain, loss )

        tp :: rest ->
            let
                delta =
                    tp.elevation - prevEle

                newGainLoss =
                    if delta > 0 then
                        ( gain + delta, loss )

                    else
                        ( gain, loss - delta )
            in
            if tp.distance >= dist then
                newGainLoss

            else
                cumulativeGainLossHelper dist tp.elevation newGainLoss rest



-- OPTIONS PANEL


viewOptionsPanel : Model -> Html Msg
viewOptionsPanel model =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "justify-content" "center"
        , Html.Attributes.style "overflow" "auto"
        , Html.Attributes.class "narrow"
        ]
        (if not model.showOptions then
            [ Html.p
                [ Html.Events.onClick <| ShowOptions True
                , Html.Attributes.style "transform" "rotate(90deg)"
                , Html.Attributes.style "white-space" "nowrap"
                , Html.Attributes.style "width" "1em"
                ]
                [ Html.text "(show options)" ]
            ]

         else
            [ Html.div [ Html.Attributes.class "options" ] <|
                List.concat
                    [ -- Header
                      [ Html.h2 [] [ Html.text "Options" ]
                      , Html.p [ Html.Events.onClick <| ShowOptions False ] [ Html.text "(hide)" ]
                      , Html.hr [] []
                      ]

                    -- Upload button
                    , [ Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.style "justify-content" "center"
                            , Html.Attributes.style "align-items" "center"
                            ]
                            (List.concat
                                [ [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "upload GPX" OpenFileBrowser ]
                                , viewTrackNavigationButtons model
                                ]
                            )
                      , Html.hr [] []
                      ]

                    -- Shared: Category filtering
                    , viewCategoryFilterOptions model

                    -- Tab-specific options
                    , case model.activeTab of
                        ElevationProfileTab ->
                            viewElevationProfileOptions model

                        CuesheetTab ->
                            viewCuesheetOptionsPanel model

                        WaypointsTab ->
                            []

                    -- Location tracking
                    , viewLocationOptions model
                    ]
            ]
        )


viewTrackNavigationButtons : Model -> List (Html Msg)
viewTrackNavigationButtons model =
    case model.tracks of
        Loaded tracks ->
            List.concat
                [ if listPopulated tracks.prev then
                    [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "PREV" NavigateToPrevious ]

                  else
                    []
                , if listPopulated tracks.next then
                    [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "NEXT" NavigateToNext ]

                  else
                    []
                ]

        _ ->
            []


viewCategoryFilterOptions : Model -> List (Html Msg)
viewCategoryFilterOptions model =
    [ optionGroup "Waypoint categories"
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
                , Html.Attributes.selected (not model.categoryFilterEnabled)
                ]
                [ Html.text "all" ]
            , Html.option
                [ Html.Attributes.value "filtered"
                , Html.Attributes.selected model.categoryFilterEnabled
                ]
                [ Html.text "filtered" ]
            ]
            :: (if model.categoryFilterEnabled then
                    [ Html.fieldset []
                        ((model.filteredCategories
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
    , Html.hr [] []
    ]


viewElevationProfileOptions : Model -> List (Html Msg)
viewElevationProfileOptions model =
    let
        ep =
            model.elevationProfile
    in
    [ optionGroup "Font size"
        [ Html.input
            [ Html.Attributes.type_ "range"
            , Html.Attributes.min "1"
            , Html.Attributes.max "50"
            , Html.Attributes.value <| String.fromFloat ep.fontSize
            , Html.Events.onInput (String.toFloat >> Maybe.withDefault 15 >> UpdateFontSize)
            ]
            []
        ]
    , optionGroup "Track height"
        [ Html.input
            [ Html.Attributes.type_ "range"
            , Html.Attributes.min "1"
            , Html.Attributes.max "400"
            , Html.Attributes.value <| String.fromInt ep.trackHeight
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
            , Html.Attributes.value <| String.fromFloat ep.trackThickness
            , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1 >> UpdateTrackThickness)
            ]
            []
        ]
    , optionGroup "Waypoint stroke colour"
        [ Html.textarea
            [ Html.Attributes.placeholder "Waypoint stroke colour..."
            , Html.Attributes.value ep.waypointStrokeColor
            , Html.Events.onInput <| WaypointStrokeColourChange
            ]
            []
        ]
    , optionGroup "Intensity"
        (List.concat
            [ [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ]
                    (if ep.showIntensity then
                        "HIDE INTENSITY"

                     else
                        "SHOW INTENSITY"
                    )
                    (ShowIntensity (not ep.showIntensity))
              ]
            , if ep.showIntensity then
                [ Html.input
                    [ Html.Attributes.type_ "range"
                    , Html.Attributes.min "100"
                    , Html.Attributes.max "20000"
                    , Html.Attributes.step "50"
                    , Html.Attributes.value <| String.fromFloat ep.intensityTau
                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 500 >> UpdateIntensityTau)
                    ]
                    []
                , Html.text ("τ = " ++ String.fromFloat ep.intensityTau ++ "m")
                ]

              else
                []
            ]
        )
    , optionGroup "Splits"
        [ Html.input
            [ Html.Attributes.type_ "range"
            , Html.Attributes.min "1"
            , Html.Attributes.max "10"
            , Html.Attributes.value <| String.fromInt ep.splits
            , Html.Events.onInput (String.toInt >> Maybe.map (clamp 1 10) >> Maybe.withDefault 1 >> UpdateSplits)
            ]
            []
        , Html.text (String.fromInt ep.splits)
        ]
    , optionGroup "Position"
        (let
            maxDist =
                maybeFromloadableResource model.tracks
                    |> Maybe.andThen (\ts -> List.maximum (List.map .distance ts.current.trackpoints))
                    |> Maybe.withDefault 1
         in
         List.concat
            [ [ Html.input
                    [ Html.Attributes.type_ "range"
                    , Html.Attributes.min "0"
                    , Html.Attributes.max (String.fromFloat maxDist)
                    , Html.Attributes.step "100"
                    , Html.Attributes.value (ep.manualPosition |> Maybe.map String.fromFloat |> Maybe.withDefault "0")
                    , Html.Events.onInput (String.toFloat >> Maybe.map Just >> Maybe.withDefault Nothing >> UpdateManualPosition)
                    ]
                    []
              ]
            , case ep.manualPosition of
                Just _ ->
                    [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "Clear position" (UpdateManualPosition Nothing) ]

                Nothing ->
                    []
            ]
        )
    , Html.hr [] []
    ]


viewCuesheetOptionsPanel : Model -> List (Html Msg)
viewCuesheetOptionsPanel model =
    let
        cs =
            model.cuesheet

        maxDistance =
            maybeFromloadableResource model.tracks
                |> Maybe.map (\ts -> getFinishDistance ts)

        maybeTracks =
            maybeFromloadableResource model.tracks

        allWaypoints =
            maybeTracks |> Maybe.map (\ts -> ts.current.waypoints) |> Maybe.withDefault []

        filteredWps =
            maybeTracks
                |> Maybe.map
                    (\ts ->
                        if model.categoryFilterEnabled then
                            cuesFilterByCategory model.filteredCategories
                                (if cs.showStartFinish then
                                    injectStartFinish (getFinishDistance ts) ts.current.gainLoss ts.current.waypoints

                                 else
                                    ts.current.waypoints
                                )

                        else if cs.showStartFinish then
                            injectStartFinish (getFinishDistance ts) ts.current.gainLoss ts.current.waypoints

                        else
                            ts.current.waypoints
                    )
                |> Maybe.withDefault []

        indexedFiltered =
            indexedFilteredWaypoints allWaypoints filteredWps

        parseModeDropdown maybeStr =
            case maybeStr of
                Just "to waypoint" ->
                    let
                        defaultIdx =
                            List.head indexedFiltered |> Maybe.map Tuple.first |> Maybe.withDefault 0
                    in
                    UpdateTotalDistanceDisplay (Just (ToWaypoint defaultIdx))

                Just "from waypoint" ->
                    let
                        defaultIdx =
                            List.head indexedFiltered |> Maybe.map Tuple.first |> Maybe.withDefault 0
                    in
                    UpdateTotalDistanceDisplay (Just (FromWaypoint defaultIdx))

                _ ->
                    maybeStr
                        |> Maybe.map parseTotalDistanceDisplay
                        |> Maybe.withDefault Nothing
                        |> UpdateTotalDistanceDisplay
    in
    [ optionGroup "Start/Finish"
        [ checkbox cs.showStartFinish (UpdateShowStartFinish (not cs.showStartFinish)) "Show start/finish"
        ]
    , Html.hr [] []
    , optionGroup "Total distance"
        ([ Dropdown.dropdown
            (Dropdown.Options
                [ Dropdown.Item (formatTotalDistanceDisplay FromZero) (formatTotalDistanceDisplay FromZero) True
                , Dropdown.Item (formatTotalDistanceDisplay ToFinish) (formatTotalDistanceDisplay ToFinish) True
                , Dropdown.Item (formatTotalDistanceDisplay ToPoint) (formatTotalDistanceDisplay ToPoint) True
                , Dropdown.Item "to waypoint" "to waypoint" True
                , Dropdown.Item "from waypoint" "from waypoint" True
                , Dropdown.Item (formatTotalDistanceDisplay None) (formatTotalDistanceDisplay None) True
                ]
                Nothing
                parseModeDropdown
            )
            []
            (Just <| formatTotalDistanceDisplayLabel cs.totalDistanceDisplay)
         ]
            ++ (case cs.totalDistanceDisplay of
                    ToPoint ->
                        [ Html.p []
                            [ Html.input
                                [ Html.Attributes.type_ "number"
                                , Html.Attributes.min "0"
                                , maxDistance |> Maybe.map (String.fromFloat >> Html.Attributes.max) |> Maybe.withDefault (Html.Attributes.disabled True)
                                , Html.Attributes.value <| String.fromFloat cs.referencePoint
                                , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1000 >> UpdateReferencePoint)
                                ]
                                []
                            ]
                        ]

                    ToWaypoint selectedIdx ->
                        [ viewWaypointSelector indexedFiltered selectedIdx ]

                    FromWaypoint selectedIdx ->
                        [ viewWaypointSelector indexedFiltered selectedIdx ]

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
            , Html.Attributes.value <| String.fromFloat cs.position
            , Html.Events.onInput (String.toFloat >> Maybe.withDefault 0.0 >> UpdatePosition)
            ]
            []
        ]
    , optionGroup "Spacing"
        [ Html.input
            [ Html.Attributes.type_ "range"
            , Html.Attributes.min "1"
            , Html.Attributes.max "50"
            , Html.Attributes.value <| String.fromInt cs.itemSpacing
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
            , Html.Attributes.value <| String.fromInt cs.distanceDetail
            , Html.Events.onInput (String.toInt >> Maybe.withDefault defaultDistanceDetail >> UpdateDistanceDetail)
            ]
            []
        ]
    , Html.hr [] []
    ]


viewLocationOptions : Model -> List (Html Msg)
viewLocationOptions model =
    case model.tracks of
        Loaded _ ->
            List.concat
                [ [ Html.hr [] []
                  , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "Refresh Location" RequestLocation
                  , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ]
                        (if model.trackingEnabled then
                            "Stop Tracking"

                         else
                            "Start Tracking"
                        )
                        ToggleTracking
                  ]
                , if model.trackingEnabled then
                    [ optionGroup ("Interval: " ++ String.fromInt model.trackingIntervalSec ++ "s")
                        [ Html.input
                            [ Html.Attributes.type_ "range"
                            , Html.Attributes.min "10"
                            , Html.Attributes.max "300"
                            , Html.Attributes.step "10"
                            , Html.Attributes.value <| String.fromInt model.trackingIntervalSec
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
                            (case model.locationError of
                                Just err ->
                                    Location.locationErrorToString err

                                Nothing ->
                                    case model.location of
                                        Just loc ->
                                            "Accuracy: " ++ String.fromFloat (toFloat (round (loc.accuracy * 10)) / 10) ++ "m"

                                        Nothing ->
                                            "No location fix"
                            )
                        ]
                  ]
                ]

        _ ->
            []



-- SHARED VIEW HELPERS


viewErrorPanel : String -> Html Msg
viewErrorPanel error =
    Html.div [ Html.Attributes.class "error_panel" ] [ Html.text error ]


viewButton : String -> Msg -> Html Msg
viewButton text onClickMsg =
    viewButtonWithAttributes [] text onClickMsg


viewButtonWithAttributes : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButtonWithAttributes attrs text onClickMsg =
    Html.button
        ([ Html.Events.onClick onClickMsg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


viewWaypointSelector : List ( Int, Waypoint ) -> Int -> Html Msg
viewWaypointSelector indexed selectedIdx =
    Dropdown.dropdown
        (Dropdown.Options
            (indexed
                |> List.map
                    (\( idx, wp ) ->
                        let
                            label =
                                wp.name ++ " (km " ++ formatKm 1 wp.distance ++ ")"
                        in
                        Dropdown.Item (String.fromInt idx) label True
                    )
            )
            Nothing
            (\maybeStr ->
                case maybeStr |> Maybe.andThen String.toInt of
                    Just idx ->
                        UpdateSelectedWaypoint idx

                    Nothing ->
                        Ignore
            )
        )
        []
        (Just (String.fromInt selectedIdx))


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



-- TOTAL DISTANCE DISPLAY


parseTotalDistanceDisplay : String -> Maybe TotalDistanceDisplay
parseTotalDistanceDisplay v =
    case v of
        "from zero" ->
            Just FromZero

        "to finish" ->
            Just ToFinish

        "to point" ->
            Just ToPoint

        "hide" ->
            Just None

        _ ->
            if String.startsWith "to waypoint" v then
                case String.split ":" v of
                    [ _, idxStr ] ->
                        String.toInt idxStr |> Maybe.map ToWaypoint

                    _ ->
                        Just (ToWaypoint 0)

            else if String.startsWith "from waypoint" v then
                case String.split ":" v of
                    [ _, idxStr ] ->
                        String.toInt idxStr |> Maybe.map FromWaypoint

                    _ ->
                        Just (FromWaypoint 0)

            else
                Nothing


formatTotalDistanceDisplay : TotalDistanceDisplay -> String
formatTotalDistanceDisplay v =
    case v of
        FromZero ->
            "from zero"

        ToFinish ->
            "to finish"

        ToPoint ->
            "to point"

        ToWaypoint idx ->
            "to waypoint:" ++ String.fromInt idx

        FromWaypoint idx ->
            "from waypoint:" ++ String.fromInt idx

        None ->
            "hide"


formatTotalDistanceDisplayLabel : TotalDistanceDisplay -> String
formatTotalDistanceDisplayLabel v =
    case v of
        ToWaypoint _ ->
            "to waypoint"

        FromWaypoint _ ->
            "from waypoint"

        other ->
            formatTotalDistanceDisplay other



-- TAB SERIALIZATION


parseTab : String -> Maybe Tab
parseTab s =
    case s of
        "elevationProfile" ->
            Just ElevationProfileTab

        "cuesheet" ->
            Just CuesheetTab

        "waypoints" ->
            Just WaypointsTab

        _ ->
            Nothing


formatTab : Tab -> String
formatTab tab =
    case tab of
        ElevationProfileTab ->
            "elevationProfile"

        CuesheetTab ->
            "cuesheet"

        WaypointsTab ->
            "waypoints"



-- ENCODE/DECODE STATE


storedStateFromModel : Model -> StoredState
storedStateFromModel model =
    { tracks = maybeFromloadableResource model.tracks
    , activeTab = Just (formatTab model.activeTab)
    , showOptions = Just model.showOptions
    , trackingIntervalSec = Just model.trackingIntervalSec
    , categoryFilterEnabled = Just model.categoryFilterEnabled
    , filteredCategories = Just model.filteredCategories
    , fontSize = Just model.elevationProfile.fontSize
    , trackHeight = Just model.elevationProfile.trackHeight
    , trackThickness = Just model.elevationProfile.trackThickness
    , waypointStrokeColor = Just model.elevationProfile.waypointStrokeColor
    , showIntensity = Just model.elevationProfile.showIntensity
    , intensityTau = Just model.elevationProfile.intensityTau
    , manualPosition = model.elevationProfile.manualPosition
    , splits = Just model.elevationProfile.splits
    , totalDistanceDisplay = Just (formatTotalDistanceDisplay model.cuesheet.totalDistanceDisplay)
    , referencePoint = Just model.cuesheet.referencePoint
    , itemSpacing = Just model.cuesheet.itemSpacing
    , distanceDetail = Just model.cuesheet.distanceDetail
    , showStartFinish = Just model.cuesheet.showStartFinish
    }


encodeSavedState : Model -> String
encodeSavedState model =
    let
        state =
            storedStateFromModel model
    in
    Json.Encode.object
        (List.filterMap
            identity
            [ state.tracks |> Maybe.map (\tracks -> ( "tracks", Zipper.encode GpxApi.encodeTrack tracks ))
            , state.activeTab |> Maybe.map (\tab -> ( "activeTab", Json.Encode.string tab ))
            , state.showOptions |> Maybe.map (\show -> ( "showOptions", Json.Encode.bool show ))
            , state.trackingIntervalSec |> Maybe.map (\interval -> ( "trackingIntervalSec", Json.Encode.int interval ))
            , state.categoryFilterEnabled |> Maybe.map (\enabled -> ( "categoryFilterEnabled", Json.Encode.bool enabled ))
            , state.filteredCategories |> Maybe.map (\cats -> ( "filteredCategories", Json.Encode.dict identity Json.Encode.bool cats ))
            , state.fontSize |> Maybe.map (\size -> ( "fontSize", Json.Encode.float size ))
            , state.trackHeight |> Maybe.map (\height -> ( "trackHeight", Json.Encode.int height ))
            , state.trackThickness |> Maybe.map (\thickness -> ( "trackThickness", Json.Encode.float thickness ))
            , state.waypointStrokeColor |> Maybe.map (\colour -> ( "waypointStrokeColor", Json.Encode.string colour ))
            , state.showIntensity |> Maybe.map (\show -> ( "showIntensity", Json.Encode.bool show ))
            , state.intensityTau |> Maybe.map (\tau -> ( "intensityTau", Json.Encode.float tau ))
            , state.manualPosition |> Maybe.map (\pos -> ( "manualPosition", Json.Encode.float pos ))
            , state.splits |> Maybe.map (\n -> ( "splits", Json.Encode.int n ))
            , state.totalDistanceDisplay |> Maybe.map (\tdd -> ( "totalDistanceDisplay", Json.Encode.string tdd ))
            , state.referencePoint |> Maybe.map (\point -> ( "referencePoint", Json.Encode.float point ))
            , state.itemSpacing |> Maybe.map (\spacing -> ( "itemSpacing", Json.Encode.int spacing ))
            , state.distanceDetail |> Maybe.map (\detail -> ( "distanceDetail", Json.Encode.int detail ))
            , state.showStartFinish |> Maybe.map (\show -> ( "showStartFinish", Json.Encode.bool show ))
            ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : Json.Decode.Decoder StoredState
storedStateDecoder =
    Json.Decode.map5 StoredState
        (Json.Decode.maybe (Json.Decode.field "tracks" (Zipper.decoder GpxApi.decodeTrack)))
        (Json.Decode.maybe (Json.Decode.field "activeTab" Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field "showOptions" Json.Decode.bool))
        (Json.Decode.maybe (Json.Decode.field "trackingIntervalSec" Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field "categoryFilterEnabled" Json.Decode.bool))
        |> andMap (Json.Decode.maybe (Json.Decode.field "filteredCategories" (Json.Decode.dict Json.Decode.bool)))
        |> andMap (Json.Decode.maybe (Json.Decode.field "fontSize" Json.Decode.float))
        |> andMap (Json.Decode.maybe (Json.Decode.field "trackHeight" Json.Decode.int))
        |> andMap (Json.Decode.maybe (Json.Decode.field "trackThickness" Json.Decode.float))
        |> andMap (Json.Decode.maybe (Json.Decode.field "waypointStrokeColor" Json.Decode.string))
        |> andMap (Json.Decode.maybe (Json.Decode.field "showIntensity" Json.Decode.bool))
        |> andMap (Json.Decode.maybe (Json.Decode.field "intensityTau" Json.Decode.float))
        |> andMap (Json.Decode.maybe (Json.Decode.field "manualPosition" Json.Decode.float))
        |> andMap (Json.Decode.maybe (Json.Decode.field "splits" Json.Decode.int))
        |> andMap (Json.Decode.maybe (Json.Decode.field "totalDistanceDisplay" Json.Decode.string))
        |> andMap (Json.Decode.maybe (Json.Decode.field "referencePoint" Json.Decode.float))
        |> andMap (Json.Decode.maybe (Json.Decode.field "itemSpacing" Json.Decode.int))
        |> andMap (Json.Decode.maybe (Json.Decode.field "distanceDetail" Json.Decode.int))
        |> andMap (Json.Decode.maybe (Json.Decode.field "showStartFinish" Json.Decode.bool))


andMap : Json.Decode.Decoder a -> Json.Decode.Decoder (a -> b) -> Json.Decode.Decoder b
andMap =
    Json.Decode.map2 (|>)



-- PORTS


port storeState : String -> Cmd msg


port calculateElevationProfileData : String -> Cmd msg


port receiveElevationProfileData : (String -> msg) -> Sub msg


port requestLocation : () -> Cmd msg


port receiveLocation : (Json.Decode.Value -> msg) -> Sub msg



-- GENERIC HELPERS


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
