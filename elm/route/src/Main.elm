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
import Http
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
subscriptions { state } =
    Sub.batch
        [ receiveLocation LocationReceived
        , if state.trackingEnabled then
            Time.every (toFloat state.trackingIntervalSec * 1000) Tick

          else
            Sub.none
        , receiveElevationProfileData WasmResponseReceived
        , receiveSplitProfile SplitProfileReceived
        ]



-- MODEL


type alias Navigation =
    { key : Browser.Navigation.Key
    , basePath : String
    }


type alias State =
    { tracks : LoadableResource (Zipper EditableTrack)
    , showOptions : Bool
    , activeTab : Tab

    -- Location tracking
    , location : Maybe Location.LocationState
    , locationError : Maybe Location.LocationError
    , trackingEnabled : Bool
    , trackingIntervalSec : Int

    -- Category filtering
    , categoryFilterEnabled : Bool
    , filteredCategories : Dict.Dict String Bool

    -- Waypoint editing
    , newCategoryInputs : Dict.Dict Int String

    -- View mode
    , viewMode : ViewMode

    -- View-specific options
    , elevationProfile : ElevationProfileOptions
    , cuesheet : CuesheetOptions

    -- Off-route
    , offRouteThreshold : Float
    , showOffRouteWaypoints : Bool
    , showOffRouteDistance : Bool

    -- Transient (never persisted)
    , stateDecodeError : Maybe String
    , splitSegments : Maybe GpxApi.SplitResult
    }


type alias Model =
    { nav : Navigation
    , state : State
    }


type Tab
    = ElevationProfileTab
    | CuesheetTab
    | WaypointsTab


type ViewMode
    = LiveView
    | StaticView


type ActiveSplitMode
    = EquidistantMode
    | WaypointsMode


type alias EditableTrack =
    { trackpoints : List GpxApi.TrackPoint
    , editableWaypoints : List EditableWaypoint
    , gainLoss : ( Float, Float )
    }


type alias EditableWaypoint =
    { original : GpxApi.Waypoint
    , deleted : Bool
    , overrides : WaypointOverrides
    }


type alias WaypointOverrides =
    { name : Maybe String
    , distance : Maybe Float
    , categories : Maybe (List String)
    }


emptyOverrides : WaypointOverrides
emptyOverrides =
    WaypointOverrides Nothing Nothing Nothing


editableTrackFromGpxTrack : GpxApi.Track -> EditableTrack
editableTrackFromGpxTrack track =
    { trackpoints = track.trackpoints
    , editableWaypoints = List.map (\w -> EditableWaypoint w False emptyOverrides) track.waypoints
    , gainLoss = track.gainLoss
    }


effectiveWaypoint : EditableWaypoint -> GpxApi.Waypoint
effectiveWaypoint ew =
    { distance = Maybe.withDefault ew.original.distance ew.overrides.distance
    , name = Maybe.withDefault ew.original.name ew.overrides.name
    , categories = Maybe.withDefault ew.original.categories ew.overrides.categories
    , gain = ew.original.gain
    , loss = ew.original.loss
    , offRoute = ew.original.offRoute
    }


effectiveWaypoints : List EditableWaypoint -> List GpxApi.Waypoint
effectiveWaypoints =
    List.filterMap
        (\ew ->
            if ew.deleted then
                Nothing

            else
                Just (effectiveWaypoint ew)
        )


{-| Pairs each non-deleted waypoint with its stable index in the editableWaypoints list.
-}
indexedEffectiveWaypoints : List EditableWaypoint -> List ( Int, GpxApi.Waypoint )
indexedEffectiveWaypoints =
    List.indexedMap Tuple.pair
        >> List.filterMap
            (\( i, ew ) ->
                if ew.deleted then
                    Nothing

                else
                    Just ( i, effectiveWaypoint ew )
            )


type alias ElevationProfileOptions =
    { fontSize : Float
    , trackHeight : Int
    , trackThickness : Float
    , showIntensity : Bool
    , intensityTau : Float
    , manualPosition : Maybe Float
    , activeSplitMode : ActiveSplitMode
    , splitEquidistantCount : Int
    , splitWaypointIndices : List Int
    , liveLookahead : Float
    , liveLookbehind : Float
    , labelHeightGain : Float
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


defaultElevationProfileOptions : ElevationProfileOptions
defaultElevationProfileOptions =
    { fontSize = 15
    , trackHeight = 200
    , trackThickness = 1
    , showIntensity = False
    , intensityTau = 500
    , manualPosition = Nothing
    , activeSplitMode = EquidistantMode
    , splitEquidistantCount = 1
    , splitWaypointIndices = []
    , liveLookahead = 5000
    , liveLookbehind = 2000
    , labelHeightGain = 1.0
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



-- DEFAULT MODEL


defaultState : State
defaultState =
    { tracks = NotLoaded
    , showOptions = True
    , activeTab = ElevationProfileTab
    , location = Nothing
    , locationError = Nothing
    , trackingEnabled = False
    , trackingIntervalSec = 60
    , categoryFilterEnabled = False
    , filteredCategories = Dict.empty
    , newCategoryInputs = Dict.empty
    , viewMode = StaticView
    , elevationProfile = defaultElevationProfileOptions
    , cuesheet = defaultCuesheetOptions
    , offRouteThreshold = 100
    , showOffRouteWaypoints = True
    , showOffRouteDistance = False
    , stateDecodeError = Nothing
    , splitSegments = Nothing
    }


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState url key =
    let
        nav =
            Navigation key url.path

        base =
            Model nav defaultState
    in
    case extractQueryParam "state" url of
        Just stateUrl ->
            ( base, Http.get { url = stateUrl, expect = Http.expectString StateUrlFetched } )

        Nothing ->
            case maybeState of
                Nothing ->
                    ( base, Cmd.none )

                Just stateValue ->
                    case Json.Decode.decodeValue stateDecoder stateValue of
                        Ok decoded ->
                            let
                                state =
                                    withLiveSplit decoded
                            in
                            ( Model nav state, requestSplitCmd state )

                        Err err ->
                            let
                                errorMsg =
                                    Json.Decode.errorToString err
                            in
                            ( { base | state = { defaultState | stateDecodeError = Just errorMsg } }
                            , logError ("Failed to decode stored state: " ++ errorMsg)
                            )


extractQueryParam : String -> Url.Url -> Maybe String
extractQueryParam key url =
    url.query
        |> Maybe.andThen
            (\query ->
                String.split "&" query
                    |> List.filterMap
                        (\param ->
                            case String.split "=" param of
                                [ k, v ] ->
                                    if k == key then
                                        Just (Url.percentDecode v |> Maybe.withDefault v)

                                    else
                                        Nothing

                                _ ->
                                    Nothing
                        )
                    |> List.head
            )



-- MSG


type Msg
    = Ignore
    | DismissStateDecodeError
      -- Shared
    | ShowOptions Bool
    | OpenFileBrowser
    | FileUploaded File.File
    | GPXStringed String
    | WasmResponseReceived String
    | SplitProfileReceived String
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
    | WaypointDeleted Int Bool
    | WaypointCategoryToggle Int String Bool
    | WaypointCategoryAdd Int String
    | WaypointNewCategoryInput Int String
    | ResetWaypoints
      -- Elevation profile
    | UpdateFontSize Float
    | UpdateTrackHeight Int
    | UpdateTrackThickness Float
    | UpdateLabelHeightGain Float
    | ShowIntensity Bool
    | UpdateIntensityTau Float
    | UpdateManualPosition (Maybe Float)
    | UpdateSplits Int
    | SetViewMode ViewMode
    | SetSplitMode ActiveSplitMode
    | AddSplitWaypoint
    | UpdateSplitWaypoint Int Int
    | RemoveSplitWaypoint Int
    | UpdateLiveLookahead Float
    | UpdateLiveLookbehind Float
      -- Cuesheet
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdatePosition Float
    | UpdateReferencePoint Float
    | UpdateItemSpacing Int
    | UpdateDistanceDetail Int
    | UpdateShowStartFinish Bool
    | UpdateShowOffRouteDistance Bool
    | UpdateSelectedWaypoint Int
    | UpdateOffRouteThreshold Float
    | UpdateShowOffRouteWaypoints Bool
      -- State export/import
    | ExportState
    | ImportStateFromFile
    | StateFileSelected File.File
    | StateFileRead String
    | ImportStateFromUrl String
    | StateUrlFetched (Result Http.Error String)



-- UPDATE


sortWaypointIndices : List EditableWaypoint -> List Int -> List Int
sortWaypointIndices editableWps indices =
    List.sortBy
        (\idx ->
            List.Extra.getAt idx editableWps
                |> Maybe.map (effectiveWaypoint >> .distance)
                |> Maybe.withDefault 0
        )
        indices


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        s =
            model.state

        updateState newState =
            { model | state = newState }
    in
    case msg of
        Ignore ->
            ( model, Cmd.none )

        DismissStateDecodeError ->
            ( updateState { s | stateDecodeError = Nothing }, Cmd.none )

        ShowOptions show ->
            ( updateState { s | showOptions = show }, Cmd.none )

        SwitchTab tab ->
            updateAndStoreModel (updateState { s | activeTab = tab })

        OpenFileBrowser ->
            ( model, File.Select.file [ "application/gpx+xml" ] FileUploaded )

        FileUploaded file ->
            updateAndStoreModel (updateState { s | tracks = Loading })
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
                    updateAndStoreModel
                        (updateState { s | tracks = Error ("parsing result from GPX response: " ++ Json.Decode.errorToString errMsg) })

                Ok typedResult ->
                    case typedResult of
                        Err errMsg ->
                            updateAndStoreModel
                                (updateState { s | tracks = Error ("getting profile data from GPX: " ++ errMsg) })

                        Ok gpxTracks ->
                            updateAndStoreModel
                                (updateState
                                    { s
                                        | tracks =
                                            case Zipper.fromList <| List.map editableTrackFromGpxTrack gpxTracks of
                                                Nothing ->
                                                    Error "No tracks available in uploaded GPX"

                                                Just positionalTracks ->
                                                    Loaded positionalTracks
                                        , filteredCategories = initialFilteredCategories (List.concatMap .waypoints gpxTracks)
                                        , elevationProfile =
                                            let
                                                ep =
                                                    s.elevationProfile
                                            in
                                            { ep | splitWaypointIndices = [] }
                                    }
                                )

        SplitProfileReceived string ->
            case Json.Decode.decodeString (GpxApi.decodeResult GpxApi.decodeSplitResult) string of
                Err errMsg ->
                    ( updateState { s | splitSegments = Nothing }
                    , logError ("parsing split profile response: " ++ Json.Decode.errorToString errMsg)
                    )

                Ok typedResult ->
                    case typedResult of
                        Err errMsg ->
                            ( updateState { s | splitSegments = Nothing }
                            , logError ("splitting profile: " ++ errMsg)
                            )

                        Ok splitResult ->
                            ( updateState { s | splitSegments = Just splitResult }, Cmd.none )

        NavigateToPrevious ->
            case s.tracks of
                Loaded tracks ->
                    updateAndStoreModel (updateState { s | tracks = Loaded (Zipper.navigatePrevious tracks) })

                _ ->
                    ( model, Cmd.none )

        NavigateToNext ->
            case s.tracks of
                Loaded tracks ->
                    updateAndStoreModel (updateState { s | tracks = Loaded (Zipper.navigateNext tracks) })

                _ ->
                    ( model, Cmd.none )

        -- Location
        RequestLocation ->
            ( model, requestLocation () )

        ToggleTracking ->
            let
                nowEnabled =
                    not s.trackingEnabled
            in
            if nowEnabled then
                updateAndStoreModel (updateState { s | trackingEnabled = True })
                    |> Tuple.mapSecond (\cmd -> Cmd.batch [ cmd, requestLocation () ])

            else
                updateAndStoreModel (updateState { s | trackingEnabled = False })

        SetTrackingInterval interval ->
            updateAndStoreModel (updateState { s | trackingIntervalSec = interval })

        Tick _ ->
            ( model, requestLocation () )

        LocationReceived value ->
            case Json.Decode.decodeValue Location.decodeLocationResult value of
                Ok (Ok pos) ->
                    case s.tracks of
                        Loaded tracks ->
                            let
                                gpsPos =
                                    Location.LatLon pos.lat pos.lon

                                matchedDist =
                                    Location.findNearestTrackPoint gpsPos tracks.current.trackpoints
                                        |> Maybe.map .distance
                                        |> Maybe.withDefault 0

                                cs =
                                    s.cuesheet
                            in
                            ( updateState
                                (withLiveSplit
                                    { s
                                        | location = Just (Location.LocationState gpsPos pos.accuracy matchedDist)
                                        , locationError = Nothing
                                        , cuesheet = { cs | position = matchedDist }
                                    }
                                )
                            , Cmd.none
                            )

                        _ ->
                            ( updateState { s | locationError = Nothing }, Cmd.none )

                Ok (Err locErr) ->
                    ( updateState { s | locationError = Just locErr }, Cmd.none )

                -- JSON decode failure; treat as unavailable
                Err _ ->
                    ( updateState { s | locationError = Just Location.PositionUnavailable }, Cmd.none )

        -- Category filtering
        CategoryEnabled category enabled ->
            let
                newCategories =
                    Dict.insert category enabled s.filteredCategories
            in
            updateAndStoreModel (updateState <| correctWaypointSelectionInState { s | filteredCategories = newCategories })

        UpdateCategoryFilterEnabled enabled ->
            updateAndStoreModel (updateState <| correctWaypointSelectionInState { s | categoryFilterEnabled = enabled })

        SetAllCategoriesEnabled enabled ->
            updateAndStoreModel (updateState <| correctWaypointSelectionInState { s | filteredCategories = Dict.map (\_ _ -> enabled) s.filteredCategories })

        -- Waypoint editing
        WaypointNameChange i name ->
            case s.tracks of
                Loaded tracks ->
                    updateAndStoreModel
                        (updateState
                            { s
                                | tracks =
                                    Loaded <|
                                        Zipper.updateCurrent
                                            (\current -> updateEditableWaypoint current i (\ew -> updateOverrides (\o -> { o | name = Just name }) ew))
                                            tracks
                            }
                        )

                _ ->
                    ( model, Cmd.none )

        WaypointDistanceChange i dist ->
            case s.tracks of
                Loaded tracks ->
                    updateAndStoreModel
                        (updateState
                            { s
                                | tracks =
                                    Loaded <|
                                        Zipper.updateCurrent
                                            (\current -> updateEditableWaypoint current i (\ew -> updateOverrides (\o -> { o | distance = Just dist }) ew))
                                            tracks
                            }
                        )

                _ ->
                    ( model, Cmd.none )

        WaypointDeleted i deleted ->
            case s.tracks of
                Loaded tracks ->
                    let
                        ep =
                            s.elevationProfile
                    in
                    updateAndStoreModel
                        (updateState
                            { s
                                | tracks =
                                    Loaded <|
                                        Zipper.updateCurrent
                                            (\current -> updateEditableWaypoint current i (\ew -> { ew | deleted = deleted }))
                                            tracks
                                , elevationProfile =
                                    { ep
                                        | splitWaypointIndices =
                                            if deleted then
                                                -- remove split waypoint if it no longer exists
                                                List.filter (\idx -> idx /= i) ep.splitWaypointIndices

                                            else
                                                ep.splitWaypointIndices
                                    }
                            }
                        )

                _ ->
                    ( model, Cmd.none )

        WaypointCategoryToggle i cat add ->
            case s.tracks of
                Loaded tracks ->
                    let
                        updateCats ew =
                            let
                                currentCats =
                                    Maybe.withDefault ew.original.categories ew.overrides.categories

                                o =
                                    ew.overrides
                            in
                            { ew
                                | overrides =
                                    { o
                                        | categories =
                                            Just
                                                (if add then
                                                    if List.member cat currentCats then
                                                        currentCats

                                                    else
                                                        currentCats ++ [ cat ]

                                                 else
                                                    List.filter (\c -> c /= cat) currentCats
                                                )
                                    }
                            }

                        newTracks =
                            Zipper.updateCurrent
                                (\current -> updateEditableWaypoint current i updateCats)
                                tracks

                        allEffectiveWaypoints =
                            List.concatMap (.editableWaypoints >> effectiveWaypoints) (newTracks.prev ++ [ newTracks.current ] ++ newTracks.next)

                        newFilteredCategories =
                            if add then
                                if Dict.member cat s.filteredCategories then
                                    s.filteredCategories

                                else
                                    Dict.insert cat True s.filteredCategories

                            else
                                let
                                    catStillUsed =
                                        List.any (\w -> List.member cat w.categories) allEffectiveWaypoints
                                in
                                if catStillUsed then
                                    s.filteredCategories

                                else
                                    Dict.remove cat s.filteredCategories
                    in
                    updateAndStoreModel
                        (updateState
                            { s
                                | tracks = Loaded newTracks
                                , filteredCategories = newFilteredCategories
                            }
                        )

                _ ->
                    ( model, Cmd.none )

        WaypointNewCategoryInput i value ->
            ( updateState { s | newCategoryInputs = Dict.insert i value s.newCategoryInputs }, Cmd.none )

        WaypointCategoryAdd i _ ->
            let
                trimmed =
                    String.trim (Dict.get i s.newCategoryInputs |> Maybe.withDefault "")
            in
            if String.isEmpty trimmed then
                ( model, Cmd.none )

            else
                case s.tracks of
                    Loaded tracks ->
                        let
                            updateCats ew =
                                let
                                    currentCats =
                                        Maybe.withDefault ew.original.categories ew.overrides.categories

                                    o =
                                        ew.overrides
                                in
                                if List.member trimmed currentCats then
                                    ew

                                else
                                    { ew | overrides = { o | categories = Just (currentCats ++ [ trimmed ]) } }

                            newFilteredCategories =
                                if Dict.member trimmed s.filteredCategories then
                                    s.filteredCategories

                                else
                                    Dict.insert trimmed True s.filteredCategories
                        in
                        updateAndStoreModel
                            (updateState
                                { s
                                    | tracks =
                                        Loaded <|
                                            Zipper.updateCurrent
                                                (\current -> updateEditableWaypoint current i updateCats)
                                                tracks
                                    , filteredCategories = newFilteredCategories
                                    , newCategoryInputs = Dict.remove i s.newCategoryInputs
                                }
                            )

                    _ ->
                        ( model, Cmd.none )

        ResetWaypoints ->
            case s.tracks of
                Loaded tracks ->
                    updateAndStoreModel
                        (updateState
                            { s
                                | tracks =
                                    Loaded <|
                                        Zipper.updateCurrent
                                            (\current ->
                                                { current
                                                    | editableWaypoints =
                                                        List.map
                                                            (\ew -> { ew | deleted = False, overrides = emptyOverrides })
                                                            current.editableWaypoints
                                                }
                                            )
                                            tracks
                            }
                        )

                _ ->
                    ( model, Cmd.none )

        -- Elevation profile options
        UpdateFontSize size ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | fontSize = size } })

        UpdateTrackHeight height ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | trackHeight = height } })

        UpdateTrackThickness thickness ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | trackThickness = thickness } })

        UpdateLabelHeightGain gain ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | labelHeightGain = gain } })

        ShowIntensity show ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | showIntensity = show } })

        UpdateIntensityTau tau ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | intensityTau = tau } })

        UpdateManualPosition pos ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | manualPosition = pos } })

        UpdateSplits n ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | splitEquidistantCount = n } })

        SetViewMode mode ->
            updateAndStoreModel (updateState { s | viewMode = mode })

        SetSplitMode mode ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | activeSplitMode = mode } })

        AddSplitWaypoint ->
            let
                ep =
                    s.elevationProfile

                editableWps =
                    maybeFromloadableResource s.tracks
                        |> Maybe.map (.current >> .editableWaypoints)
                        |> Maybe.withDefault []

                availableIndices =
                    indexedEffectiveWaypoints editableWps |> List.map Tuple.first

                indices =
                    ep.splitWaypointIndices

                firstAvailable =
                    availableIndices
                        |> List.filter (\i -> not (List.member i indices))
                        |> List.head
            in
            case firstAvailable of
                Just idx ->
                    let
                        newIndices =
                            sortWaypointIndices editableWps (idx :: indices)
                    in
                    updateAndStoreModel (updateState { s | elevationProfile = { ep | splitWaypointIndices = newIndices } })

                Nothing ->
                    ( model, Cmd.none )

        -- splitWaypointIndices holds a list of waypoint indices (into editableWaypoints).
        -- splitListPos is a position within that list; newWaypointIdx is an editableWaypoints index.
        UpdateSplitWaypoint splitListPos newWaypointIdx ->
            let
                ep =
                    s.elevationProfile

                newIndices =
                    maybeFromloadableResource s.tracks
                        |> Maybe.map
                            (.current
                                >> .editableWaypoints
                                >> (\editableWaypoints ->
                                        List.Extra.setAt splitListPos newWaypointIdx ep.splitWaypointIndices
                                            |> sortWaypointIndices editableWaypoints
                                   )
                            )
                        |> Maybe.withDefault []
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | splitWaypointIndices = newIndices } })

        RemoveSplitWaypoint splitListPos ->
            let
                ep =
                    s.elevationProfile

                newIndices =
                    List.Extra.removeAt splitListPos ep.splitWaypointIndices
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | splitWaypointIndices = newIndices } })

        UpdateLiveLookahead val ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | liveLookahead = val } })

        UpdateLiveLookbehind val ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | liveLookbehind = val } })

        -- Cuesheet options
        UpdateTotalDistanceDisplay maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\selection ->
                        let
                            cs =
                                s.cuesheet
                        in
                        updateAndStoreModel (updateState { s | cuesheet = { cs | totalDistanceDisplay = selection } })
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdatePosition position ->
            let
                cs =
                    s.cuesheet
            in
            updateAndStoreModel (updateState { s | cuesheet = { cs | position = position } })

        UpdateReferencePoint point ->
            let
                cs =
                    s.cuesheet
            in
            updateAndStoreModel (updateState { s | cuesheet = { cs | referencePoint = point } })

        UpdateItemSpacing spacing ->
            let
                cs =
                    s.cuesheet
            in
            updateAndStoreModel (updateState { s | cuesheet = { cs | itemSpacing = spacing } })

        UpdateDistanceDetail detail ->
            let
                cs =
                    s.cuesheet
            in
            updateAndStoreModel (updateState { s | cuesheet = { cs | distanceDetail = detail } })

        UpdateShowStartFinish show ->
            let
                cs =
                    s.cuesheet
            in
            updateAndStoreModel (updateState { s | cuesheet = { cs | showStartFinish = show } })

        UpdateShowOffRouteDistance show ->
            updateAndStoreModel (updateState { s | showOffRouteDistance = show })

        UpdateSelectedWaypoint idx ->
            let
                cs =
                    s.cuesheet

                newDisplay =
                    case cs.totalDistanceDisplay of
                        ToWaypoint _ ->
                            ToWaypoint idx

                        FromWaypoint _ ->
                            FromWaypoint idx

                        other ->
                            other
            in
            updateAndStoreModel (updateState { s | cuesheet = { cs | totalDistanceDisplay = newDisplay } })

        UpdateOffRouteThreshold threshold ->
            updateAndStoreModel (updateState { s | offRouteThreshold = threshold })

        UpdateShowOffRouteWaypoints show ->
            updateAndStoreModel (updateState { s | showOffRouteWaypoints = show })

        ExportState ->
            ( model, downloadState (encodeSavedState { s | showOptions = False }) )

        ImportStateFromFile ->
            ( model, File.Select.file [ "application/json" ] StateFileSelected )

        StateFileSelected file ->
            ( model, Task.perform StateFileRead (File.toString file) )

        StateFileRead jsonString ->
            restoreState jsonString model

        ImportStateFromUrl url ->
            ( model, Http.get { url = url, expect = Http.expectString StateUrlFetched } )

        StateUrlFetched (Ok jsonString) ->
            restoreState jsonString model
                |> Tuple.mapSecond (\cmd -> Cmd.batch [ cmd, Browser.Navigation.replaceUrl model.nav.key model.nav.basePath ])

        StateUrlFetched (Err err) ->
            ( updateState
                { s
                    | stateDecodeError =
                        Just
                            ("Failed to fetch state from URL: "
                                ++ (case err of
                                        Http.BadUrl u ->
                                            "Bad URL: " ++ u

                                        Http.Timeout ->
                                            "Request timed out"

                                        Http.NetworkError ->
                                            "Network error (check CORS headers)"

                                        Http.BadStatus status ->
                                            "HTTP " ++ String.fromInt status

                                        Http.BadBody body ->
                                            "Bad response: " ++ body
                                   )
                            )
                }
            , Cmd.none
            )


restoreState : String -> Model -> ( Model, Cmd Msg )
restoreState jsonString model =
    case Json.Decode.decodeString stateDecoder jsonString of
        Ok decoded ->
            let
                restored =
                    { model | state = withLiveSplit decoded }
            in
            ( restored, Cmd.batch [ storeState (encodeSavedState restored.state), requestSplitCmd restored.state ] )

        Err err ->
            let
                s =
                    model.state
            in
            ( { model | state = { s | stateDecodeError = Just (Json.Decode.errorToString err) } }, Cmd.none )


updateAndStoreModel : Model -> ( Model, Cmd Msg )
updateAndStoreModel model =
    let
        state =
            withLiveSplit model.state
    in
    ( { model | state = state }, Cmd.batch [ storeState (encodeSavedState state), requestSplitCmd state ] )


requestSplitCmd : State -> Cmd Msg
requestSplitCmd state =
    case state.viewMode of
        LiveView ->
            Cmd.none

        StaticView ->
            requestSplitCmdWasm state


requestSplitCmdWasm : State -> Cmd Msg
requestSplitCmdWasm state =
    case state.tracks of
        Loaded tracks ->
            let
                filteredWaypoints =
                    effectiveWaypoints tracks.current.editableWaypoints
                        |> filterWaypoints (waypointPredicates state)
            in
            requestSplitProfile
                (Json.Encode.encode 0
                    (Json.Encode.object
                        ([ ( "track", GpxApi.encodeTrack <| GpxApi.Track tracks.current.trackpoints filteredWaypoints tracks.current.gainLoss ) ]
                            ++ (case state.elevationProfile.activeSplitMode of
                                    EquidistantMode ->
                                        [ ( "mode", Json.Encode.string "equidistant" )
                                        , ( "count", Json.Encode.int state.elevationProfile.splitEquidistantCount )
                                        ]

                                    WaypointsMode ->
                                        let
                                            distances =
                                                state.elevationProfile.splitWaypointIndices
                                                    |> List.filterMap
                                                        (\i ->
                                                            List.Extra.getAt i tracks.current.editableWaypoints
                                                                |> Maybe.andThen
                                                                    (\ew ->
                                                                        if ew.deleted then
                                                                            Nothing

                                                                        else
                                                                            Just (effectiveWaypoint ew).distance
                                                                    )
                                                        )
                                                    |> List.sort
                                        in
                                        [ ( "mode", Json.Encode.string "waypoints" )
                                        , ( "distances", Json.Encode.list Json.Encode.float distances )
                                        ]
                               )
                        )
                    )
                )

        _ ->
            Cmd.none


computeLiveSplitFromState : State -> Maybe GpxApi.SplitResult
computeLiveSplitFromState state =
    case state.tracks of
        Loaded tracks ->
            let
                tps =
                    tracks.current.trackpoints

                maxDist =
                    List.reverse tps |> List.head |> Maybe.map .distance |> Maybe.withDefault 0

                ep =
                    state.elevationProfile

                ( rangeStart, rangeEnd ) =
                    case effectivePosition state of
                        Just p ->
                            ( max 0 (p - ep.liveLookbehind), min maxDist (p + ep.liveLookahead) )

                        Nothing ->
                            ( 0, maxDist )

                segTps =
                    tps |> List.filter (\tp -> tp.distance >= rangeStart && tp.distance <= rangeEnd)

                segWps =
                    effectiveWaypoints tracks.current.editableWaypoints
                        |> filterWaypoints (waypointPredicates state)
                        |> List.filter (\wp -> wp.distance >= rangeStart && wp.distance <= rangeEnd)

                shift record =
                    { record | distance = record.distance - rangeStart }
            in
            Just
                { segments =
                    [ { trackpoints = List.map shift segTps
                      , waypoints = List.map shift segWps
                      , gainLoss = computeGainLoss segTps
                      }
                    ]
                , boundaries = [ ( rangeStart, rangeEnd ) ]
                }

        _ ->
            Nothing


computeGainLoss : List GpxApi.TrackPoint -> ( Float, Float )
computeGainLoss tps =
    case List.reverse tps of
        last :: _ ->
            case tps of
                first :: _ ->
                    ( last.gain - first.gain, last.loss - first.loss )

                [] ->
                    ( 0, 0 )

        [] ->
            ( 0, 0 )


withLiveSplit : State -> State
withLiveSplit state =
    if state.viewMode == LiveView then
        { state | splitSegments = computeLiveSplitFromState state }

    else
        state



-- HELPERS


updateEditableWaypoint : EditableTrack -> Int -> (EditableWaypoint -> EditableWaypoint) -> EditableTrack
updateEditableWaypoint track i fn =
    { track | editableWaypoints = List.Extra.updateAt i fn track.editableWaypoints }


updateOverrides : (WaypointOverrides -> WaypointOverrides) -> EditableWaypoint -> EditableWaypoint
updateOverrides fn ew =
    { ew | overrides = fn ew.overrides }


lastTrackpointDistance : List GpxApi.TrackPoint -> Float
lastTrackpointDistance trackpoints =
    List.Extra.last trackpoints
        |> Maybe.map .distance
        |> Maybe.withDefault 0


unknownCategory : String
unknownCategory =
    ""


startFinishCategory : String
startFinishCategory =
    "Start/Finish"


initialFilteredCategories : List GpxApi.Waypoint -> Dict.Dict String Bool
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


filterWaypoints : List (GpxApi.Waypoint -> Bool) -> List GpxApi.Waypoint -> List GpxApi.Waypoint
filterWaypoints filters =
    List.filter (\waypoint -> List.all (\filter -> filter waypoint) filters)


waypointPredicates : State -> List (GpxApi.Waypoint -> Bool)
waypointPredicates state =
    List.filterMap identity
        [ if state.categoryFilterEnabled then
            Just (categoryPredicate state.filteredCategories)

          else
            Nothing
        , if state.showOffRouteWaypoints then
            Nothing

          else
            Just (offRoutePredicate state.offRouteThreshold)
        , case ( state.viewMode, effectivePosition state ) of
            ( LiveView, Just pos ) ->
                let
                    ep =
                        state.elevationProfile
                in
                Just (\wp -> wp.distance >= pos - ep.liveLookbehind && wp.distance <= pos + ep.liveLookahead)

            _ ->
                Nothing
        ]


categoryPredicate : Dict.Dict String Bool -> GpxApi.Waypoint -> Bool
categoryPredicate categories w =
    let
        includeCategory cat =
            Dict.get cat categories |> Maybe.withDefault True
    in
    case w.categories of
        [] ->
            includeCategory unknownCategory

        cats ->
            List.any includeCategory cats


trimWaypointCategories : Dict.Dict String Bool -> List GpxApi.Waypoint -> List GpxApi.Waypoint
trimWaypointCategories categories =
    List.map
        (\w ->
            case w.categories of
                [] ->
                    w

                cats ->
                    { w | categories = List.filter (\cat -> Dict.get cat categories |> Maybe.withDefault True) cats }
        )


offRoutePredicate : Float -> GpxApi.Waypoint -> Bool
offRoutePredicate threshold w =
    w.offRoute <= threshold


indexedFilteredWaypoints : List GpxApi.Waypoint -> List GpxApi.Waypoint -> List ( Int, GpxApi.Waypoint )
indexedFilteredWaypoints allWaypoints filtered =
    allWaypoints
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, wp ) -> List.member wp filtered)


correctWaypointSelection : TotalDistanceDisplay -> List ( Int, GpxApi.Waypoint ) -> TotalDistanceDisplay
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


correctWaypointSelectionInState : State -> State
correctWaypointSelectionInState s =
    case maybeFromloadableResource s.tracks of
        Nothing ->
            s

        Just tracks ->
            let
                allWaypoints =
                    effectiveWaypoints tracks.current.editableWaypoints

                filtered =
                    filterWaypoints (waypointPredicates s) allWaypoints

                indexed =
                    indexedFilteredWaypoints allWaypoints filtered

                cs =
                    s.cuesheet

                corrected =
                    correctWaypointSelection cs.totalDistanceDisplay indexed
            in
            { s | cuesheet = { cs | totalDistanceDisplay = corrected } }


effectivePosition : State -> Maybe Float
effectivePosition state =
    case state.elevationProfile.manualPosition of
        Just _ ->
            state.elevationProfile.manualPosition

        Nothing ->
            state.location |> Maybe.map .matchedDistance


injectStartFinish : Float -> ( Float, Float ) -> List GpxApi.Waypoint -> List GpxApi.Waypoint
injectStartFinish finishDist ( totalGain, totalLoss ) waypoints =
    let
        hasWaypointAtDistance d =
            List.any (\w -> w.distance == d) waypoints

        withStart =
            if hasWaypointAtDistance 0 then
                waypoints

            else
                GpxApi.Waypoint 0 "Start" [ startFinishCategory ] 0 0 0 :: waypoints
    in
    if hasWaypointAtDistance finishDist then
        withStart

    else
        withStart ++ [ GpxApi.Waypoint finishDist "Finish" [ startFinishCategory ] totalGain totalLoss 0 ]



-- VIEW


view : Model -> Browser.Document Msg
view { state } =
    Browser.Document "Route"
        [ Html.div
            [ Html.Attributes.class "flex-container"
            , Html.Attributes.class "row"
            , Html.Attributes.class "page"
            , Html.Attributes.style "height" "100%"
            ]
            (viewStateDecodeError state.stateDecodeError
                ++ (case state.tracks of
                        NotLoaded ->
                            [ viewOptionsPanel state
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
                            [ viewOptionsPanel state
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
                            [ viewOptionsPanel state
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
                            [ viewOptionsPanel state
                            , Html.div
                                [ Html.Attributes.class "flex-container"
                                , Html.Attributes.class "column"
                                , Html.Attributes.class "wide"
                                , Html.Attributes.style "height" "100%"
                                , Html.Attributes.style "overflow" "auto"
                                ]
                                [ viewTabBar state.activeTab
                                , viewTrackNavigation tracks
                                , case state.activeTab of
                                    ElevationProfileTab ->
                                        viewElevationProfileTab state tracks

                                    CuesheetTab ->
                                        viewCuesheetTab state tracks

                                    WaypointsTab ->
                                        viewWaypointsTab state tracks
                                ]
                            ]
                   )
            )
        ]


viewStateDecodeError : Maybe String -> List (Html Msg)
viewStateDecodeError maybeError =
    case maybeError of
        Nothing ->
            []

        Just error ->
            [ Html.div
                [ Html.Attributes.style "background" "#fff3cd"
                , Html.Attributes.style "color" "#856404"
                , Html.Attributes.style "padding" "0.75em 1em"
                , Html.Attributes.style "margin" "0.5em"
                , Html.Attributes.style "border-radius" "4px"
                , Html.Attributes.style "display" "flex"
                , Html.Attributes.style "justify-content" "space-between"
                , Html.Attributes.style "align-items" "flex-start"
                , Html.Attributes.style "gap" "1em"
                , Html.Attributes.style "width" "100%"
                ]
                [ Html.div []
                    [ Html.strong [] [ Html.text "Failed to restore saved state: " ]
                    , Html.text (String.left 500 error)
                    ]
                , Html.button
                    [ Html.Events.onClick DismissStateDecodeError
                    , Html.Attributes.style "background" "none"
                    , Html.Attributes.style "border" "none"
                    , Html.Attributes.style "cursor" "pointer"
                    , Html.Attributes.style "font-size" "1.2em"
                    , Html.Attributes.style "color" "#856404"
                    ]
                    [ Html.text "×" ]
                ]
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
        , viewButton [] "Upload GPX" OpenFileBrowser
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


viewTrackNavigation : Zipper EditableTrack -> Html Msg
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


viewElevationProfileTab : State -> Zipper EditableTrack -> Html Msg
viewElevationProfileTab state tracks =
    let
        ep =
            state.elevationProfile

        trackMaxElevation =
            Maybe.withDefault 1 <| List.maximum <| List.map .elevation tracks.current.trackpoints

        trackMinElevation =
            Maybe.withDefault 1 <| List.minimum <| List.map .elevation tracks.current.trackpoints

        pos =
            effectivePosition state

        fullIntensity =
            if ep.showIntensity then
                computeIntensity ep.intensityTau tracks.current.trackpoints

            else
                []

        ( trackMinIntensity, trackMaxIntensity ) =
            List.foldl
                (\pt ( mn, mx ) -> ( min mn pt.intensity, max mx pt.intensity ))
                ( 1 / 0, -(1 / 0) )
                fullIntensity
    in
    case state.splitSegments of
        Nothing ->
            Html.text ""

        Just splitResult ->
            let
                profileViews =
                    List.map2 Tuple.pair splitResult.boundaries splitResult.segments
                        |> List.indexedMap
                            (\segIndex ( ( segStart, segEnd ), seg ) ->
                                let
                                    segMaxDistance =
                                        List.reverse seg.trackpoints
                                            |> List.head
                                            |> Maybe.map .distance
                                            |> Maybe.withDefault (segEnd - segStart)

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
                                            |> downsample (profileSvgWidth // 1)

                                    downsampledSeg =
                                        { seg | trackpoints = downsample profileSvgWidth seg.trackpoints }
                                in
                                profile segIndex downsampledSeg seg.trackpoints segMaxDistance trackMinElevation trackMaxElevation ep.fontSize ep.trackHeight ep.trackThickness ep.labelHeightGain state.offRouteThreshold segPosition segIntensity trackMinIntensity trackMaxIntensity
                            )
            in
            Html.div [] profileViews


profileSvgWidth : Int
profileSvgWidth =
    500


elevationTicks : Float -> Float -> List Float
elevationTicks minElev maxElev =
    let
        range =
            maxElev - minElev

        interval =
            if range > 1000 then
                500

            else if range > 300 then
                100

            else if range > 100 then
                50

            else
                25

        firstTick =
            toFloat (ceiling (minElev / interval)) * interval

        buildTicks current acc =
            if current > maxElev then
                List.reverse acc

            else
                buildTicks (current + interval) (current :: acc)
    in
    buildTicks firstTick []


profile : Int -> GpxApi.Track -> List GpxApi.TrackPoint -> Float -> Float -> Float -> Float -> Int -> Float -> Float -> Float -> Maybe Float -> List { distance : Float, intensity : Float } -> Float -> Float -> Html Msg
profile segmentIndex track fullTrackpoints maxDistance minElevation maxElevation fontSize trackHeight trackThickness labelHeightGain offRouteThreshold maybePosition intensityPoints minIntensity maxIntensity =
    let
        waypointTextHeight =
            track.waypoints
                |> List.map (\w -> String.length w.name)
                |> List.maximum
                |> Maybe.withDefault 0
                |> (\len -> max 100 (round (toFloat len * 0.6 * fontSize * labelHeightGain)))

        svgHeight =
            trackHeight + waypointTextHeight

        calc =
            xyCalculator
                { svgHeight = toFloat trackHeight
                , svgWidth = toFloat profileSvgWidth
                , maxDistance = maxDistance
                , minElevation = minElevation
                , maxElevation = maxElevation
                }
    in
    Html.div
        [ Html.Attributes.style "margin-top" "16px"
        , Html.Attributes.style "padding" "0 8px"
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
            [ Svg.Attributes.viewBox <| "-50 -5 " ++ String.fromInt (profileSvgWidth + 55) ++ " " ++ (String.fromInt <| svgHeight + 10)
            ]
            [ -- intensity shading
              if List.isEmpty intensityPoints then
                Svg.g [] []

              else
                renderIntensityShading segmentIndex (toFloat profileSvgWidth) maxDistance (toFloat trackHeight) intensityPoints minIntensity maxIntensity
            , -- elevation ticks
              Svg.g []
                (elevationTicks minElevation maxElevation
                    |> List.concatMap
                        (\tickElev ->
                            let
                                y =
                                    calc.y tickElev
                            in
                            [ Svg.line
                                [ Svg.Attributes.x1 "-5"
                                , Svg.Attributes.y1 y
                                , Svg.Attributes.x2 "0"
                                , Svg.Attributes.y2 y
                                , Svg.Attributes.stroke "grey"
                                , Svg.Attributes.strokeWidth "1"
                                ]
                                []
                            , Svg.text_
                                [ Svg.Attributes.x "-8"
                                , Svg.Attributes.y y
                                , Svg.Attributes.textAnchor "end"
                                , Svg.Attributes.dominantBaseline "central"
                                , Svg.Attributes.fontSize "10"
                                , Svg.Attributes.fill "grey"
                                ]
                                [ Svg.text (String.fromInt (round tickElev)) ]
                            ]
                        )
                )
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
                                    calc.y <| interpolateWaypointElevation fullTrackpoints waypoint.distance - 5

                                isOffRoute =
                                    waypoint.offRoute > offRouteThreshold

                                strokeColor =
                                    if isOffRoute then
                                        "orange"

                                    else
                                        "lightgray"
                            in
                            [ Svg.line
                                [ Svg.Attributes.x1 <| x
                                , Svg.Attributes.y1 <| svgBottom
                                , Svg.Attributes.x2 <| x
                                , Svg.Attributes.y2 <| y
                                , Svg.Attributes.stroke strokeColor
                                , Svg.Attributes.strokeWidth "1"
                                ]
                                []
                            , Svg.text_
                                ([ Svg.Attributes.fontSize <| String.fromFloat fontSize
                                 , Svg.Attributes.dominantBaseline "text-top"
                                 , Svg.Attributes.transform <| "translate(" ++ x ++ ", " ++ paddedWaypointTextY ++ ") rotate(90)"
                                 ]
                                    ++ (if isOffRoute then
                                            [ Svg.Attributes.fill "orange" ]

                                        else
                                            []
                                       )
                                )
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
                            calc.y (interpolateWaypointElevation fullTrackpoints posDistance)
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
                 , ( ( 0, 0 ), ( 0, profileSvgWidth ) )
                 , ( ( trackHeight, profileSvgWidth ), ( trackHeight, 0 ) )
                 , ( ( trackHeight, profileSvgWidth ), ( 0, profileSvgWidth ) )
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


downsample : Int -> List a -> List a
downsample maxPoints list =
    let
        len =
            List.length list
    in
    if len <= maxPoints then
        list

    else
        let
            stride =
                toFloat (len - 1) / toFloat (maxPoints - 1)

            keepIndices =
                List.range 0 (maxPoints - 1)
                    |> List.map (\i -> round (toFloat i * stride))
                    |> List.sort
        in
        list
            |> List.indexedMap Tuple.pair
            |> List.foldl
                (\( idx, item ) ( remaining, result ) ->
                    case remaining of
                        [] ->
                            ( remaining, result )

                        keepIdx :: restKeep ->
                            if idx == keepIdx then
                                ( restKeep, item :: result )

                            else
                                ( remaining, result )
                )
                ( keepIndices, [] )
            |> (\( _, result ) -> List.reverse result)


interpolateWaypointElevation : List GpxApi.TrackPoint -> Float -> Float
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


resolveElevationProfileSVGLine : XYCalculator -> List GpxApi.TrackPoint -> String -> Svg.Svg msg
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


computeIntensity : Float -> List GpxApi.TrackPoint -> List { distance : Float, intensity : Float }
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


renderIntensityShading : Int -> Float -> Float -> Float -> List { distance : Float, intensity : Float } -> Float -> Float -> Svg.Svg msg
renderIntensityShading segmentIndex svgWidth maxDistance trackHeightFloat intensityPoints minIntensity maxIntensity =
    let
        intensityRange =
            maxIntensity - minIntensity

        gradientId =
            "intensity-gradient-" ++ String.fromInt segmentIndex

        stops =
            List.map
                (\point ->
                    let
                        normalized =
                            if intensityRange > 0 then
                                (point.intensity - minIntensity) / intensityRange

                            else
                                0

                        offsetPct =
                            if maxDistance > 0 then
                                String.fromFloat (point.distance / maxDistance * 100) ++ "%"

                            else
                                "0%"
                    in
                    Svg.stop
                        [ Svg.Attributes.offset offsetPct
                        , Svg.Attributes.stopColor (intensityColor normalized)
                        , Svg.Attributes.stopOpacity "0.3"
                        ]
                        []
                )
                intensityPoints
    in
    Svg.g []
        [ Svg.defs []
            [ Svg.linearGradient
                [ Svg.Attributes.id gradientId
                , Svg.Attributes.x1 "0"
                , Svg.Attributes.y1 "0"
                , Svg.Attributes.x2 "1"
                , Svg.Attributes.y2 "0"
                ]
                stops
            ]
        , Svg.rect
            [ Svg.Attributes.x "0"
            , Svg.Attributes.y "0"
            , Svg.Attributes.width (String.fromFloat svgWidth)
            , Svg.Attributes.height (String.fromFloat trackHeightFloat)
            , Svg.Attributes.fill ("url(#" ++ gradientId ++ ")")
            ]
            []
        ]


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
    = InfoWaypoint GpxApi.Waypoint
    | InfoPosition GpxApi.Waypoint
    | Ride Float ( Float, Float )


viewCuesheetTab : State -> Zipper EditableTrack -> Html Msg
viewCuesheetTab state tracks =
    let
        cs =
            state.cuesheet

        currentEffectiveWaypoints =
            effectiveWaypoints tracks.current.editableWaypoints

        currentFinishDistance =
            lastTrackpointDistance tracks.current.trackpoints

        waypointsWithStartFinish =
            if cs.showStartFinish then
                injectStartFinish currentFinishDistance tracks.current.gainLoss currentEffectiveWaypoints

            else
                currentEffectiveWaypoints

        filteredWaypoints =
            filterWaypoints (waypointPredicates state) waypointsWithStartFinish
                |> trimWaypointCategories state.filteredCategories

        positionWaypoint =
            case ( effectivePosition state, state.viewMode ) of
                ( Just pos, LiveView ) ->
                    cumulativeGainLossAtDistance pos tracks.current.trackpoints
                        |> Result.toMaybe
                        |> Maybe.map (\( g, l ) -> GpxApi.Waypoint pos "Current position" [] g l 0)

                _ ->
                    Nothing

        waypointsWithPosition =
            case positionWaypoint of
                Just pw ->
                    List.sortBy .distance (pw :: filteredWaypoints)

                Nothing ->
                    filteredWaypoints

        refWaypoint =
            case cs.totalDistanceDisplay of
                ToWaypoint idx ->
                    List.Extra.getAt idx currentEffectiveWaypoints

                FromWaypoint idx ->
                    List.Extra.getAt idx currentEffectiveWaypoints

                _ ->
                    Nothing

        refPointEle =
            case refWaypoint of
                Just wp ->
                    ( wp.gain, wp.loss )

                Nothing ->
                    cumulativeGainLossAtDistance cs.referencePoint tracks.current.trackpoints
                        |> Result.withDefault ( 0, 0 )
    in
    Html.div []
        [ cuesheetSvg state.offRouteThreshold state.showOffRouteDistance (Maybe.map .distance positionWaypoint) waypointsWithPosition cs currentFinishDistance refPointEle refWaypoint
        ]


viewWaypointsTab : State -> Zipper EditableTrack -> Html Msg
viewWaypointsTab state tracks =
    let
        maxDistance =
            lastTrackpointDistance tracks.current.trackpoints

        anyWaypointEdited =
            List.any
                (\ew -> ew.deleted || ew.overrides /= emptyOverrides)
                tracks.current.editableWaypoints
    in
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.5em"
        , Html.Attributes.style "padding" "0.5em"
        ]
        [ if anyWaypointEdited then
            viewButton [] "Reset Waypoints" ResetWaypoints

          else
            Html.text ""
        , Html.div
            [ Html.Attributes.style "display" "flex"
            , Html.Attributes.style "flex-direction" "column"
            , Html.Attributes.style "gap" "0.5em"
            ]
            (tracks.current.editableWaypoints
                |> List.indexedMap Tuple.pair
                |> List.filterMap
                    (\( i, ew ) ->
                        let
                            wp =
                                effectiveWaypoint ew

                            predicates =
                                waypointPredicates state
                        in
                        if not (List.all (\f -> f wp) predicates) then
                            Nothing

                        else if ew.deleted then
                            Just (viewDeletedWaypoint i ew)

                        else
                            Just
                                (Html.div
                                    [ Html.Attributes.style "border" "1px solid #ddd"
                                    , Html.Attributes.style "border-radius" "6px"
                                    , Html.Attributes.style "padding" "0.5em"
                                    , Html.Attributes.style "display" "flex"
                                    , Html.Attributes.style "flex-direction" "column"
                                    , Html.Attributes.style "gap" "0.4em"
                                    , Html.Attributes.style "background" "#fafafa"
                                    ]
                                    [ Html.div
                                        [ Html.Attributes.style "display" "flex"
                                        , Html.Attributes.style "gap" "0.4em"
                                        , Html.Attributes.style "align-items" "center"
                                        ]
                                        [ Html.input
                                            [ Html.Attributes.type_ "number"
                                            , Html.Attributes.min "0"
                                            , maxDistance |> (String.fromFloat >> Html.Attributes.max)
                                            , Html.Attributes.value <| String.fromFloat wp.distance
                                            , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1000 >> WaypointDistanceChange i)
                                            , Html.Attributes.style "width" "7em"
                                            , Html.Attributes.style "flex-shrink" "0"
                                            ]
                                            []
                                        , Html.input
                                            [ Html.Attributes.type_ "text"
                                            , Html.Attributes.placeholder "Waypoint name..."
                                            , Html.Attributes.value wp.name
                                            , Html.Events.onInput <| WaypointNameChange i
                                            , Html.Attributes.style "flex" "1"
                                            , Html.Attributes.style "min-width" "0"
                                            ]
                                            []
                                        , viewButton [] "X" (WaypointDeleted i True)
                                        ]
                                    , viewWaypointCategories i wp.categories (List.filter (\c -> c /= unknownCategory) (Dict.keys state.filteredCategories)) (Dict.get i state.newCategoryInputs |> Maybe.withDefault "")
                                    ]
                                )
                    )
            )
        ]


viewDeletedWaypoint : Int -> EditableWaypoint -> Html Msg
viewDeletedWaypoint i ew =
    Html.div
        [ Html.Attributes.style "border" "1px solid #eee"
        , Html.Attributes.style "border-radius" "6px"
        , Html.Attributes.style "padding" "0.5em"
        , Html.Attributes.style "opacity" "0.5"
        , Html.Attributes.style "display" "flex"
        , Html.Attributes.style "align-items" "center"
        , Html.Attributes.style "justify-content" "space-between"
        , Html.Attributes.style "gap" "0.5em"
        ]
        [ Html.span
            [ Html.Attributes.style "text-decoration" "line-through" ]
            [ Html.text ew.original.name ]
        , viewButton [] "Undo" (WaypointDeleted i False)
        ]


viewWaypointCategories : Int -> List String -> List String -> String -> Html Msg
viewWaypointCategories idx waypointCategories allCategories newCatInput =
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.4em"
        ]
        [ Html.div
            [ Html.Attributes.style "display" "flex"
            , Html.Attributes.style "flex-wrap" "wrap"
            , Html.Attributes.style "gap" "0.25em"
            ]
            (allCategories
                |> List.map
                    (\cat ->
                        let
                            isChecked =
                                List.member cat waypointCategories
                        in
                        Html.label
                            [ Html.Attributes.style "display" "inline-flex"
                            , Html.Attributes.style "align-items" "center"
                            , Html.Attributes.style "gap" "0.15em"
                            , Html.Attributes.style "padding" "0.15em 0.4em"
                            , Html.Attributes.style "border-radius" "4px"
                            , Html.Attributes.style "border" "1px solid #ccc"
                            , Html.Attributes.style "font-size" "0.85em"
                            , Html.Attributes.style "cursor" "pointer"
                            , Html.Attributes.style "background"
                                (if isChecked then
                                    "#e0edff"

                                 else
                                    "#fff"
                                )
                            , Html.Attributes.style "white-space" "nowrap"
                            ]
                            [ Html.input
                                [ Html.Attributes.type_ "checkbox"
                                , Html.Attributes.checked isChecked
                                , Html.Events.onCheck (WaypointCategoryToggle idx cat)
                                , Html.Attributes.style "margin" "0"
                                ]
                                []
                            , Html.text cat
                            ]
                    )
            )
        , Html.div
            [ Html.Attributes.style "display" "flex"
            , Html.Attributes.style "gap" "0.25em"
            , Html.Attributes.style "align-items" "center"
            ]
            [ Html.input
                [ Html.Attributes.type_ "text"
                , Html.Attributes.placeholder "New category..."
                , Html.Attributes.value newCatInput
                , Html.Events.onInput (WaypointNewCategoryInput idx)
                , Html.Attributes.style "flex" "1"
                , Html.Attributes.style "min-width" "0"
                ]
                []
            , viewButton [] "Add" (WaypointCategoryAdd idx "")
            ]
        ]


cuesheetSvg : Float -> Bool -> Maybe Float -> List GpxApi.Waypoint -> CuesheetOptions -> Float -> ( Float, Float ) -> Maybe GpxApi.Waypoint -> Html Msg
cuesheetSvg offRouteThreshold showOffRouteDistance positionDistance waypoints cs finishDist refPointEle refWaypoint =
    let
        info =
            waypointInfos positionDistance cs.position waypoints

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
                        let
                            renderWaypointItem fillAttrs waypoint =
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

                                    isOffRoute =
                                        waypoint.offRoute > offRouteThreshold

                                    offRouteLabel =
                                        String.fromInt (round waypoint.offRoute) ++ "m off"

                                    waypointInfo =
                                        List.filterMap identity
                                            [ waypointDistance
                                            , waypointEle
                                            , case waypoint.categories of
                                                [] ->
                                                    Nothing

                                                cats ->
                                                    Just <| String.join ", " cats
                                            , if isOffRoute then
                                                Just <| "⚠ " ++ offRouteLabel

                                              else if showOffRouteDistance && waypoint.offRoute > 0 then
                                                Just offRouteLabel

                                              else
                                                Nothing
                                            ]

                                    waypointInfoLines =
                                        if List.isEmpty waypointInfo then
                                            [ "◉" ]

                                        else
                                            waypointInfo
                                in
                                Svg.g [ translate ]
                                    (Svg.text_
                                        ([ Svg.Attributes.x (String.fromInt <| svgContentLeftStart + 10)
                                         , Svg.Attributes.dominantBaseline "middle"
                                         , Svg.Attributes.y <| String.fromInt (cs.itemSpacing // 2)
                                         ]
                                            ++ fillAttrs
                                        )
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
                        in
                        case item of
                            InfoWaypoint waypoint ->
                                renderWaypointItem
                                    (if waypoint.offRoute > offRouteThreshold then
                                        [ Svg.Attributes.fill "orange" ]

                                     else
                                        []
                                    )
                                    waypoint

                            InfoPosition waypoint ->
                                renderWaypointItem [ Svg.Attributes.fill "steelblue" ] waypoint

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


waypointInfos : Maybe Float -> Float -> List GpxApi.Waypoint -> List Info
waypointInfos positionDistance position waypoints =
    let
        infoConstructor wp =
            if Just wp.distance == positionDistance then
                InfoPosition wp

            else
                InfoWaypoint wp
    in
    List.foldl
        (\el accum ->
            if el.distance < position then
                accum

            else
                ( Just el
                , (infoConstructor el
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


cumulativeGainLossAtDistance : Float -> List GpxApi.TrackPoint -> Result String ( Float, Float )
cumulativeGainLossAtDistance dist trackpoints =
    -- TODO: interpolate between bracketing trackpoints when dist falls between two points,
    -- rather than snapping to the next one (could use interpolateTrackpointAt)
    case List.Extra.find (\tp -> tp.distance >= dist) trackpoints of
        Just tp ->
            Ok ( tp.gain, tp.loss )

        Nothing ->
            case List.Extra.last trackpoints of
                Just tp ->
                    Ok ( tp.gain, tp.loss )

                Nothing ->
                    Err "no trackpoints found for gain/loss lookup"



-- OPTIONS PANEL


viewOptionsPanel : State -> Html Msg
viewOptionsPanel state =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "overflow" "auto"
        , Html.Attributes.class "narrow"
        , Html.Attributes.style "flex-shrink" "0"
        ]
        (if not state.showOptions then
            [ Html.p
                [ Html.Events.onClick <| ShowOptions True
                , Html.Attributes.style "transform" "rotate(90deg)"
                , Html.Attributes.style "white-space" "nowrap"
                , Html.Attributes.style "width" "1em"
                , Html.Attributes.style "margin" "auto 0"
                ]
                [ Html.text "(show options)" ]
            ]

         else
            [ Html.div [ Html.Attributes.class "options", Html.Attributes.style "margin" "auto 0" ] <|
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
                                [ [ viewButton [ Html.Attributes.style "width" "100%" ] "upload GPX" OpenFileBrowser ]
                                , viewTrackNavigationButtons state
                                ]
                            )
                      , Html.hr [] []
                      ]
                    , viewStateExportImport
                    , [ Html.hr [] [] ]

                    -- Shared: Category filtering
                    , viewCategoryFilterOptions state

                    -- Shared: View mode
                    , [ optionGroup "View"
                            [ Html.select
                                [ Html.Events.onInput
                                    (\v ->
                                        case v of
                                            "live" ->
                                                SetViewMode LiveView

                                            _ ->
                                                SetViewMode StaticView
                                    )
                                ]
                                [ Html.option
                                    [ Html.Attributes.value "static"
                                    , Html.Attributes.selected (state.viewMode == StaticView)
                                    ]
                                    [ Html.text "Static" ]
                                , Html.option
                                    [ Html.Attributes.value "live"
                                    , Html.Attributes.selected (state.viewMode == LiveView)
                                    ]
                                    [ Html.text "Live" ]
                                ]
                            ]
                      ]
                    , case state.viewMode of
                        LiveView ->
                            let
                                ep =
                                    state.elevationProfile
                            in
                            [ optionGroup "Live window"
                                [ Html.text ("Lookbehind: " ++ formatKm 1 ep.liveLookbehind)
                                , Html.input
                                    [ Html.Attributes.type_ "range"
                                    , Html.Attributes.min "0"
                                    , Html.Attributes.max "50000"
                                    , Html.Attributes.step "500"
                                    , Html.Attributes.value <| String.fromFloat ep.liveLookbehind
                                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 2000 >> UpdateLiveLookbehind)
                                    ]
                                    []
                                , Html.text ("Lookahead: " ++ formatKm 1 ep.liveLookahead)
                                , Html.input
                                    [ Html.Attributes.type_ "range"
                                    , Html.Attributes.min "0"
                                    , Html.Attributes.max "200000"
                                    , Html.Attributes.step "500"
                                    , Html.Attributes.value <| String.fromFloat ep.liveLookahead
                                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 5000 >> UpdateLiveLookahead)
                                    ]
                                    []
                                ]
                            ]

                        StaticView ->
                            []

                    -- Tab-specific options
                    , case state.activeTab of
                        ElevationProfileTab ->
                            viewElevationProfileOptions state

                        CuesheetTab ->
                            viewCuesheetOptionsPanel state

                        WaypointsTab ->
                            []

                    -- Location tracking
                    , viewLocationOptions state
                    ]
            ]
        )


viewStateExportImport : List (Html Msg)
viewStateExportImport =
    [ Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "align-items" "center"
        , Html.Attributes.style "gap" "0.25em"
        ]
        [ Html.div
            [ Html.Attributes.class "flex-container"
            , Html.Attributes.style "gap" "0.25em"
            , Html.Attributes.style "width" "100%"
            ]
            [ viewButton [ Html.Attributes.style "flex" "1" ] "export state" ExportState
            , viewButton [ Html.Attributes.style "flex" "1" ] "import state" ImportStateFromFile
            ]
        , Html.form
            [ Html.Events.preventDefaultOn "submit"
                (Json.Decode.at [ "target", "0", "value" ] Json.Decode.string
                    |> Json.Decode.map (\url -> ( ImportStateFromUrl url, True ))
                )
            , Html.Attributes.class "flex-container"
            , Html.Attributes.style "width" "100%"
            , Html.Attributes.style "gap" "0.25em"
            ]
            [ Html.input
                [ Html.Attributes.type_ "url"
                , Html.Attributes.placeholder "state URL"
                , Html.Attributes.style "flex" "1"
                , Html.Attributes.style "min-width" "0"
                ]
                []
            , Html.button [ Html.Attributes.type_ "submit" ] [ Html.text "fetch" ]
            ]
        ]
    ]


viewTrackNavigationButtons : State -> List (Html Msg)
viewTrackNavigationButtons state =
    case state.tracks of
        Loaded tracks ->
            List.concat
                [ if not (List.isEmpty tracks.prev) then
                    [ viewButton [ Html.Attributes.style "width" "100%" ] "PREV" NavigateToPrevious ]

                  else
                    []
                , if not (List.isEmpty tracks.next) then
                    [ viewButton [ Html.Attributes.style "width" "100%" ] "NEXT" NavigateToNext ]

                  else
                    []
                ]

        _ ->
            []


viewCategoryFilterOptions : State -> List (Html Msg)
viewCategoryFilterOptions state =
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
                , Html.Attributes.selected (not state.categoryFilterEnabled)
                ]
                [ Html.text "all" ]
            , Html.option
                [ Html.Attributes.value "filtered"
                , Html.Attributes.selected state.categoryFilterEnabled
                ]
                [ Html.text "filtered" ]
            ]
            :: (if state.categoryFilterEnabled then
                    [ Html.fieldset []
                        ((state.filteredCategories
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
    , optionGroup ("Off-route threshold: " ++ String.fromInt (round state.offRouteThreshold) ++ "m")
        [ Html.input
            [ Html.Attributes.type_ "range"
            , Html.Attributes.min "0"
            , Html.Attributes.max "1000"
            , Html.Attributes.step "10"
            , Html.Attributes.value <| String.fromFloat state.offRouteThreshold
            , Html.Events.onInput (String.toFloat >> Maybe.withDefault 100 >> UpdateOffRouteThreshold)
            ]
            []
        , checkbox state.showOffRouteWaypoints (UpdateShowOffRouteWaypoints (not state.showOffRouteWaypoints)) "Show off-route waypoints"
        , checkbox state.showOffRouteDistance (UpdateShowOffRouteDistance (not state.showOffRouteDistance)) "Show off-route distance"
        ]
    , Html.hr [] []
    ]


viewElevationProfileOptions : State -> List (Html Msg)
viewElevationProfileOptions state =
    let
        ep =
            state.elevationProfile
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
    , optionGroup "Label height"
        [ Html.input
            [ Html.Attributes.type_ "range"
            , Html.Attributes.min "0.5"
            , Html.Attributes.max "3"
            , Html.Attributes.step "0.1"
            , Html.Attributes.value <| String.fromFloat ep.labelHeightGain
            , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1 >> UpdateLabelHeightGain)
            ]
            []
        ]
    , optionGroup "Intensity"
        (List.concat
            [ [ viewButton [ Html.Attributes.style "width" "100%" ]
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
                (List.concat
                    [ [ Html.select
                            [ Html.Events.onInput
                                (\v ->
                                    case v of
                                        "waypoints" ->
                                            SetSplitMode WaypointsMode

                                        _ ->
                                            SetSplitMode EquidistantMode
                                )
                            ]
                            [ Html.option
                                [ Html.Attributes.value "equidistant"
                                , Html.Attributes.selected (ep.activeSplitMode == EquidistantMode)
                                ]
                                [ Html.text "Equidistant" ]
                            , Html.option
                                [ Html.Attributes.value "waypoints"
                                , Html.Attributes.selected (ep.activeSplitMode == WaypointsMode)
                                ]
                                [ Html.text "By waypoints" ]
                            ]
                      ]
                    , case ep.activeSplitMode of
                        EquidistantMode ->
                            [ Html.input
                                [ Html.Attributes.type_ "range"
                                , Html.Attributes.min "1"
                                , Html.Attributes.max "10"
                                , Html.Attributes.value <| String.fromInt ep.splitEquidistantCount
                                , Html.Events.onInput (String.toInt >> Maybe.map (clamp 1 10) >> Maybe.withDefault 1 >> UpdateSplits)
                                ]
                                []
                            , Html.text (String.fromInt ep.splitEquidistantCount)
                            ]

                        WaypointsMode ->
                            let
                                selectedIndices =
                                    ep.splitWaypointIndices

                                indexed =
                                    maybeFromloadableResource state.tracks
                                        |> Maybe.map (.current >> .editableWaypoints >> indexedEffectiveWaypoints)
                                        |> Maybe.withDefault []

                                -- splitListPos = position in the splits list; selectedWaypointIdx = editableWaypoints index at that position
                                dropdownRow splitListPos selectedWaypointIdx =
                                    let
                                        waypointOption ( waypointIdx, wp ) =
                                            Html.option
                                                [ Html.Attributes.value (String.fromInt waypointIdx)
                                                , Html.Attributes.selected (waypointIdx == selectedWaypointIdx)
                                                ]
                                                [ Html.text (wp.name ++ " (" ++ formatKm 1 wp.distance ++ ")") ]
                                    in
                                    Html.div [ Html.Attributes.style "display" "flex", Html.Attributes.style "gap" "0.5em", Html.Attributes.style "align-items" "center" ]
                                        [ Html.select
                                            [ Html.Events.onInput
                                                (\val ->
                                                    String.toInt val
                                                        |> Maybe.map (UpdateSplitWaypoint splitListPos)
                                                        |> Maybe.withDefault Ignore
                                                )
                                            ]
                                            (List.map waypointOption indexed)
                                        , Html.button
                                            [ Html.Events.onClick (RemoveSplitWaypoint splitListPos)
                                            , Html.Attributes.class "button-4"
                                            ]
                                            [ Html.text "Remove" ]
                                        ]
                            in
                            List.indexedMap dropdownRow selectedIndices
                                ++ [ Html.button
                                        [ Html.Events.onClick AddSplitWaypoint
                                        , Html.Attributes.class "button-4"
                                        , Html.Attributes.disabled (List.length selectedIndices >= List.length indexed)
                                        ]
                                        [ Html.text "Add" ]
                                   ]
                    ]
                )
    , optionGroup "Position"
        (let
            maxDist =
                maybeFromloadableResource state.tracks
                    |> Maybe.andThen (\ts -> List.maximum (List.map .distance ts.current.trackpoints))
                    |> Maybe.withDefault 1
         in
         List.concat
            [ [ Html.input
                    [ Html.Attributes.type_ "range"
                    , Html.Attributes.min "0"
                    , Html.Attributes.max (String.fromFloat maxDist)
                    , Html.Attributes.step "100"
                    , Html.Attributes.value (String.fromFloat (effectivePosition state |> Maybe.withDefault 0))
                    , Html.Events.onInput (String.toFloat >> Maybe.map Just >> Maybe.withDefault Nothing >> UpdateManualPosition)
                    , Html.Attributes.disabled state.trackingEnabled
                    ]
                    []
              ]
            , case ep.manualPosition of
                Just _ ->
                    if state.trackingEnabled then
                        []

                    else
                        [ viewButton [ Html.Attributes.style "width" "100%" ] "Clear position" (UpdateManualPosition Nothing) ]

                Nothing ->
                    []
            ]
        )
    , Html.hr [] []
    ]


viewCuesheetOptionsPanel : State -> List (Html Msg)
viewCuesheetOptionsPanel state =
    let
        cs =
            state.cuesheet

        maxDistance =
            maybeFromloadableResource state.tracks
                |> Maybe.map (\ts -> lastTrackpointDistance ts.current.trackpoints)

        maybeTracks =
            maybeFromloadableResource state.tracks

        filteredWps =
            maybeTracks
                |> Maybe.map
                    (\ts ->
                        let
                            currentEffective =
                                effectiveWaypoints ts.current.editableWaypoints
                        in
                        (if cs.showStartFinish then
                            injectStartFinish (lastTrackpointDistance ts.current.trackpoints) ts.current.gainLoss currentEffective

                         else
                            currentEffective
                        )
                            |> filterWaypoints (waypointPredicates state)
                            |> trimWaypointCategories state.filteredCategories
                    )
                |> Maybe.withDefault []

        indexedFiltered =
            maybeTracks
                |> Maybe.map
                    (.current
                        >> .editableWaypoints
                        >> effectiveWaypoints
                        >> (\waypoints -> indexedFilteredWaypoints waypoints filteredWps)
                    )
                |> Maybe.withDefault []

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


viewLocationOptions : State -> List (Html Msg)
viewLocationOptions state =
    case state.tracks of
        Loaded _ ->
            List.concat
                [ [ Html.hr [] []
                  , viewButton [ Html.Attributes.style "width" "100%" ]
                        (if state.trackingEnabled then
                            "Stop Tracking"

                         else
                            "Start Tracking"
                        )
                        ToggleTracking
                  , viewButton [ Html.Attributes.style "width" "100%" ] "Refresh Location" RequestLocation
                  ]
                , if state.trackingEnabled then
                    [ optionGroup ("Interval: " ++ String.fromInt state.trackingIntervalSec ++ "s")
                        [ Html.input
                            [ Html.Attributes.type_ "range"
                            , Html.Attributes.min "10"
                            , Html.Attributes.max "300"
                            , Html.Attributes.step "10"
                            , Html.Attributes.value <| String.fromInt state.trackingIntervalSec
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
                            (case state.locationError of
                                Just err ->
                                    Location.locationErrorToString err

                                Nothing ->
                                    case state.location of
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


viewButton : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButton attrs text onClickMsg =
    Html.button
        ([ Html.Events.onClick onClickMsg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


viewWaypointSelector : List ( Int, GpxApi.Waypoint ) -> Int -> Html Msg
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


encodeEditableTrack : EditableTrack -> Json.Encode.Value
encodeEditableTrack track =
    Json.Encode.object
        [ ( "trackpoints", GpxApi.encodeTrackpoints track.trackpoints )
        , ( "editableWaypoints", Json.Encode.list encodeEditableWaypoint track.editableWaypoints )
        , ( "gain", Json.Encode.float (Tuple.first track.gainLoss) )
        , ( "loss", Json.Encode.float (Tuple.second track.gainLoss) )
        ]


encodeEditableWaypoint : EditableWaypoint -> Json.Encode.Value
encodeEditableWaypoint ew =
    Json.Encode.object
        (List.filterMap identity
            [ Just ( "original", GpxApi.encodeWaypoint ew.original )
            , Just ( "deleted", Json.Encode.bool ew.deleted )
            , ew.overrides.name |> Maybe.map (\n -> ( "name", Json.Encode.string n ))
            , ew.overrides.distance |> Maybe.map (\d -> ( "distance", Json.Encode.float d ))
            , ew.overrides.categories |> Maybe.map (\cats -> ( "categories", Json.Encode.list Json.Encode.string cats ))
            ]
        )


editableTrackDecoder : Json.Decode.Decoder EditableTrack
editableTrackDecoder =
    Json.Decode.map3 EditableTrack
        (Json.Decode.field "trackpoints" GpxApi.decodeTrackpoints)
        (Json.Decode.field "editableWaypoints" (Json.Decode.list editableWaypointDecoder))
        (Json.Decode.map2 Tuple.pair
            (Json.Decode.field "gain" Json.Decode.float)
            (Json.Decode.field "loss" Json.Decode.float)
        )


editableWaypointDecoder : Json.Decode.Decoder EditableWaypoint
editableWaypointDecoder =
    Json.Decode.map3 EditableWaypoint
        (Json.Decode.field "original" GpxApi.decodeWaypoint)
        (Json.Decode.field "deleted" Json.Decode.bool)
        (Json.Decode.map3 WaypointOverrides
            (Json.Decode.maybe (Json.Decode.field "name" Json.Decode.string))
            (Json.Decode.maybe (Json.Decode.field "distance" Json.Decode.float))
            (Json.Decode.maybe (Json.Decode.field "categories" (Json.Decode.list Json.Decode.string)))
        )


encodeSavedState : State -> String
encodeSavedState state =
    let
        ep =
            state.elevationProfile

        cs =
            state.cuesheet
    in
    Json.Encode.object
        (List.filterMap
            identity
            [ maybeFromloadableResource state.tracks |> Maybe.map (\tracks -> ( "tracks", Zipper.encode encodeEditableTrack tracks ))
            , Just ( "activeTab", Json.Encode.string (formatTab state.activeTab) )
            , Just ( "showOptions", Json.Encode.bool state.showOptions )
            , Just ( "trackingIntervalSec", Json.Encode.int state.trackingIntervalSec )
            , Just ( "categoryFilterEnabled", Json.Encode.bool state.categoryFilterEnabled )
            , Just ( "filteredCategories", Json.Encode.dict identity Json.Encode.bool state.filteredCategories )
            , Just ( "fontSize", Json.Encode.float ep.fontSize )
            , Just ( "trackHeight", Json.Encode.int ep.trackHeight )
            , Just ( "trackThickness", Json.Encode.float ep.trackThickness )
            , Just ( "showIntensity", Json.Encode.bool ep.showIntensity )
            , Just ( "intensityTau", Json.Encode.float ep.intensityTau )
            , ep.manualPosition |> Maybe.map (\pos -> ( "manualPosition", Json.Encode.float pos ))
            , Just
                ( "viewMode"
                , Json.Encode.string
                    (case state.viewMode of
                        LiveView ->
                            "live"

                        StaticView ->
                            "static"
                    )
                )
            , Just
                ( "splitMode"
                , Json.Encode.string
                    (case ep.activeSplitMode of
                        EquidistantMode ->
                            "equidistant"

                        WaypointsMode ->
                            "waypoints"
                    )
                )
            , Just ( "splitEquidistantCount", Json.Encode.int ep.splitEquidistantCount )
            , Just ( "splitWaypointIndices", Json.Encode.list Json.Encode.int ep.splitWaypointIndices )
            , Just ( "liveLookahead", Json.Encode.float ep.liveLookahead )
            , Just ( "liveLookbehind", Json.Encode.float ep.liveLookbehind )
            , Just ( "labelHeightGain", Json.Encode.float ep.labelHeightGain )
            , Just ( "totalDistanceDisplay", Json.Encode.string (formatTotalDistanceDisplay cs.totalDistanceDisplay) )
            , Just ( "referencePoint", Json.Encode.float cs.referencePoint )
            , Just ( "itemSpacing", Json.Encode.int cs.itemSpacing )
            , Just ( "distanceDetail", Json.Encode.int cs.distanceDetail )
            , Just ( "showStartFinish", Json.Encode.bool cs.showStartFinish )
            , Just ( "offRouteThreshold", Json.Encode.float state.offRouteThreshold )
            , Just ( "showOffRouteWaypoints", Json.Encode.bool state.showOffRouteWaypoints )
            , Just ( "showOffRouteDistance", Json.Encode.bool state.showOffRouteDistance )
            ]
        )
        |> Json.Encode.encode 0


stateDecoder : Json.Decode.Decoder State
stateDecoder =
    let
        maybeField name decoder =
            Json.Decode.maybe (Json.Decode.field name decoder)

        defEp =
            defaultElevationProfileOptions

        defCs =
            defaultCuesheetOptions
    in
    Json.Decode.succeed
        (\tracks activeTab showOptions trackingIntervalSec categoryFilterEnabled filteredCategories fontSize trackHeight trackThickness showIntensity intensityTau manualPosition viewMode splitMode splitEquidistantCount splitWaypointIndices liveLookahead liveLookbehind labelHeightGain totalDistanceDisplay referencePoint itemSpacing distanceDetail showStartFinish showOffRouteDistance offRouteThreshold showOffRouteWaypoints ->
            { tracks = loadableResourceFromMaybe tracks
            , showOptions = showOptions |> Maybe.withDefault defaultState.showOptions
            , activeTab = activeTab |> Maybe.andThen parseTab |> Maybe.withDefault defaultState.activeTab
            , location = Nothing
            , locationError = Nothing
            , trackingEnabled = False
            , trackingIntervalSec = trackingIntervalSec |> Maybe.withDefault defaultState.trackingIntervalSec
            , categoryFilterEnabled = categoryFilterEnabled |> Maybe.withDefault defaultState.categoryFilterEnabled
            , filteredCategories = filteredCategories |> Maybe.withDefault defaultState.filteredCategories
            , newCategoryInputs = Dict.empty
            , viewMode =
                case viewMode of
                    Just "live" ->
                        LiveView

                    _ ->
                        StaticView
            , offRouteThreshold = offRouteThreshold |> Maybe.withDefault defaultState.offRouteThreshold
            , showOffRouteWaypoints = showOffRouteWaypoints |> Maybe.withDefault defaultState.showOffRouteWaypoints
            , showOffRouteDistance = showOffRouteDistance |> Maybe.withDefault defaultState.showOffRouteDistance
            , elevationProfile =
                { fontSize = fontSize |> Maybe.withDefault defEp.fontSize
                , trackHeight = trackHeight |> Maybe.withDefault defEp.trackHeight
                , trackThickness = trackThickness |> Maybe.withDefault defEp.trackThickness
                , showIntensity = showIntensity |> Maybe.withDefault defEp.showIntensity
                , intensityTau = intensityTau |> Maybe.withDefault defEp.intensityTau
                , manualPosition = manualPosition
                , activeSplitMode =
                    case splitMode of
                        Just "waypoints" ->
                            WaypointsMode

                        _ ->
                            EquidistantMode
                , splitEquidistantCount = splitEquidistantCount |> Maybe.withDefault 1
                , splitWaypointIndices = splitWaypointIndices |> Maybe.withDefault []
                , liveLookahead = liveLookahead |> Maybe.withDefault defEp.liveLookahead
                , liveLookbehind = liveLookbehind |> Maybe.withDefault defEp.liveLookbehind
                , labelHeightGain = labelHeightGain |> Maybe.withDefault defEp.labelHeightGain
                }
            , cuesheet =
                { totalDistanceDisplay = totalDistanceDisplay |> Maybe.andThen parseTotalDistanceDisplay |> Maybe.withDefault defCs.totalDistanceDisplay
                , referencePoint = referencePoint |> Maybe.withDefault defCs.referencePoint
                , position = 0
                , itemSpacing = itemSpacing |> Maybe.withDefault defCs.itemSpacing
                , distanceDetail = distanceDetail |> Maybe.withDefault defCs.distanceDetail
                , showStartFinish = showStartFinish |> Maybe.withDefault defCs.showStartFinish
                }
            , stateDecodeError = Nothing
            , splitSegments = Nothing
            }
        )
        |> andMap (maybeField "tracks" (Zipper.decoder editableTrackDecoder))
        |> andMap (maybeField "activeTab" Json.Decode.string)
        |> andMap (maybeField "showOptions" Json.Decode.bool)
        |> andMap (maybeField "trackingIntervalSec" Json.Decode.int)
        |> andMap (maybeField "categoryFilterEnabled" Json.Decode.bool)
        |> andMap (maybeField "filteredCategories" (Json.Decode.dict Json.Decode.bool))
        |> andMap (maybeField "fontSize" Json.Decode.float)
        |> andMap (maybeField "trackHeight" Json.Decode.int)
        |> andMap (maybeField "trackThickness" Json.Decode.float)
        |> andMap (maybeField "showIntensity" Json.Decode.bool)
        |> andMap (maybeField "intensityTau" Json.Decode.float)
        |> andMap (maybeField "manualPosition" Json.Decode.float)
        |> andMap (maybeField "viewMode" Json.Decode.string)
        |> andMap (maybeField "splitMode" Json.Decode.string)
        |> andMap (maybeField "splitEquidistantCount" Json.Decode.int)
        |> andMap (maybeField "splitWaypointIndices" (Json.Decode.list Json.Decode.int))
        |> andMap (maybeField "liveLookahead" Json.Decode.float)
        |> andMap (maybeField "liveLookbehind" Json.Decode.float)
        |> andMap (maybeField "labelHeightGain" Json.Decode.float)
        |> andMap (maybeField "totalDistanceDisplay" Json.Decode.string)
        |> andMap (maybeField "referencePoint" Json.Decode.float)
        |> andMap (maybeField "itemSpacing" Json.Decode.int)
        |> andMap (maybeField "distanceDetail" Json.Decode.int)
        |> andMap (maybeField "showStartFinish" Json.Decode.bool)
        |> andMap (maybeField "showOffRouteDistance" Json.Decode.bool)
        |> andMap (maybeField "offRouteThreshold" Json.Decode.float)
        |> andMap (maybeField "showOffRouteWaypoints" Json.Decode.bool)


andMap : Json.Decode.Decoder a -> Json.Decode.Decoder (a -> b) -> Json.Decode.Decoder b
andMap =
    Json.Decode.map2 (|>)



-- PORTS


port logError : String -> Cmd msg


port storeState : String -> Cmd msg


port downloadState : String -> Cmd msg


port calculateElevationProfileData : String -> Cmd msg


port receiveElevationProfileData : (String -> msg) -> Sub msg


port requestSplitProfile : String -> Cmd msg


port receiveSplitProfile : (String -> msg) -> Sub msg


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
