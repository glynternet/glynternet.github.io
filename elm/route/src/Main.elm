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
        , profileWidthChanged ProfileWidthChanged
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

    -- Position on the route (set manually or by tracking; the single source of truth)
    , position : Maybe Float

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
    , relative : RelativeOptions

    -- Off-route
    , offRouteThreshold : Float
    , showOffRouteWaypoints : Bool
    , showOffRouteDistance : Bool

    -- Transient (never persisted)
    , stateDecodeError : Maybe String
    , splitSegments : Maybe GpxApi.SplitResult
    , profilePixelWidth : Maybe Int
    }


type alias Model =
    { nav : Navigation
    , state : State
    }


type Tab
    = ElevationProfileTab
    | CuesheetTab
    | WaypointsTab
    | RelativeTab


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
    , created : Bool
    , overrides : WaypointOverrides
    }


{-| A point on the route the user has picked out: either one of the track's waypoints, or
wherever they are.

Every flow that asks the user to choose a point on the route stores one of these, so the
same selector serves all of them. `AtRoutePosition` resolves against `state.position`,
which may be unset — hence the `Maybe` on the resolvers below. It is the point on the route
nearest the rider, not the rider: a GPS fix off the route resolves to what it matched, and
the gap is the resolved waypoint's off-route distance.

`AtWaypoint` indexes `editableWaypoints`, deliberately including the deleted ones: that index
is stable, whereas a position in the resolved-and-filtered list shifts under the user as soon
as an earlier waypoint is marked deleted or filtered out. It is also the index space the
edit flows already maintain — see `removeWaypointAt`, `WaypointDeleted` and `ResetWaypoints`.

-}
type PointRef
    = AtWaypoint Int
    | AtRoutePosition


{-| Resolves a reference to the waypoint it stands for, or Nothing when it no longer stands
for one — a deleted waypoint, or `AtRoutePosition` with no position set. A position becomes a
synthetic waypoint, carrying the cumulative climb to there and, when a GPS fix is what set
the position, how far off route that fix is.

Returning a `GpxApi.Waypoint` rather than a bespoke record is what lets the cuesheet and
elevation profile treat a chosen position exactly like a chosen waypoint.

-}
resolvePointRef : Maybe Float -> Maybe Location.LocationState -> EditableTrack -> PointRef -> Maybe GpxApi.Waypoint
resolvePointRef position location track ref =
    case ref of
        AtWaypoint i ->
            List.Extra.getAt i track.editableWaypoints
                |> Maybe.andThen
                    (\ew ->
                        if ew.deleted then
                            Nothing

                        else
                            Just (effectiveWaypoint track.trackpoints ew)
                    )

        AtRoutePosition ->
            position
                |> Maybe.andThen
                    (\pos ->
                        cumulativeGainLossAtDistance pos track.trackpoints
                            |> Result.toMaybe
                            |> Maybe.map
                                (\( gain, loss ) ->
                                    GpxApi.Waypoint pos
                                        routePositionName
                                        []
                                        gain
                                        loss
                                        (location |> Maybe.map .offRouteDistance |> Maybe.withDefault 0)
                                )
                    )


{-| The route distance a reference stands for, for the flows that only need to place the
point along the route. Defined through `resolvePointRef` so there is a single answer to what
an `AtWaypoint` index means; a GPS fix cannot move a point along the route, so none is needed.
-}
refDistance : Maybe Float -> EditableTrack -> PointRef -> Maybe Float
refDistance position track =
    resolvePointRef position Nothing track >> Maybe.map .distance


{-| Remaps a reference after the waypoint at `removedIndex` has been dropped from
`editableWaypoints`, which shifts every later index down by one. A position is not addressed
by index, so it survives untouched.
-}
shiftPointRef : Int -> PointRef -> PointRef
shiftPointRef removedIndex ref =
    case ref of
        AtWaypoint i ->
            if i > removedIndex then
                AtWaypoint (i - 1)

            else
                ref

        AtRoutePosition ->
            ref


routePositionName : String
routePositionName =
    "Position on route"


{-| A waypoint reference formats as its bare index, which is what `TotalDistanceDisplay`
stored before a position was selectable — so old saved state still reads back.
Doubles as the option value in `viewPointSelector`.
-}
formatPointRef : PointRef -> String
formatPointRef ref =
    case ref of
        AtWaypoint idx ->
            String.fromInt idx

        AtRoutePosition ->
            "position"


parsePointRef : String -> Maybe PointRef
parsePointRef s =
    if s == "position" then
        Just AtRoutePosition

    else
        String.toInt s |> Maybe.map AtWaypoint


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
    , editableWaypoints = List.map (\w -> EditableWaypoint w False False emptyOverrides) track.waypoints
    , gainLoss = track.gainLoss
    }


effectiveDistance : EditableWaypoint -> Float
effectiveDistance ew =
    Maybe.withDefault ew.original.distance ew.overrides.distance


effectiveWaypoint : List GpxApi.TrackPoint -> EditableWaypoint -> GpxApi.Waypoint
effectiveWaypoint trackpoints ew =
    let
        -- A distance override relocates the waypoint along the route, so its
        -- cumulative gain/loss must be re-read at the new position; keeping the
        -- original values would report climb/descent for where it used to be.
        ( gain, loss ) =
            case ew.overrides.distance of
                Just overriddenDistance ->
                    cumulativeGainLossAtDistance overriddenDistance trackpoints
                        |> Result.withDefault ( ew.original.gain, ew.original.loss )

                Nothing ->
                    ( ew.original.gain, ew.original.loss )
    in
    { distance = effectiveDistance ew
    , name = Maybe.withDefault ew.original.name ew.overrides.name
    , categories = Maybe.withDefault ew.original.categories ew.overrides.categories
    , gain = gain
    , loss = loss
    , offRoute =
        case ew.overrides.distance of
            -- An overridden distance pins the waypoint onto the route at
            -- that point, so it is no longer off-route.
            Just _ ->
                0

            Nothing ->
                ew.original.offRoute
    }


effectiveWaypoints : EditableTrack -> List GpxApi.Waypoint
effectiveWaypoints track =
    List.filterMap
        (\ew ->
            if ew.deleted then
                Nothing

            else
                Just (effectiveWaypoint track.trackpoints ew)
        )
        track.editableWaypoints


type alias ElevationProfileOptions =
    { fontSize : Float
    , trackHeight : Int
    , trackThickness : Float
    , showIntensity : Bool
    , intensityTau : Float
    , activeSplitMode : ActiveSplitMode
    , splitEquidistantCount : Int
    , splitPoints : List PointRef
    , liveLookahead : Float
    , liveLookbehind : Float
    , labelHeightGain : Float
    , distanceMarkerInterval : Maybe Float
    , distanceMarkerSegmentEnds : Bool
    }


type alias CuesheetOptions =
    { totalDistanceDisplay : TotalDistanceDisplay
    , referencePoint : Float
    , itemSpacing : Int
    , distanceDetail : Int
    , showStartFinish : Bool
    }


{-| The two points the Relative tab compares.
-}
type alias RelativeOptions =
    { start : PointRef
    , end : PointRef
    }


type TotalDistanceDisplay
    = FromZero
    | ToFinish
    | ToPoint
    | ToWaypoint PointRef
    | FromWaypoint PointRef
    | PercentProgress
    | PercentRemaining
    | None


defaultElevationProfileOptions : ElevationProfileOptions
defaultElevationProfileOptions =
    { fontSize = 15
    , trackHeight = 200
    , trackThickness = 1
    , showIntensity = False
    , intensityTau = 500
    , activeSplitMode = EquidistantMode
    , splitEquidistantCount = 1
    , splitPoints = []
    , liveLookahead = 5000
    , liveLookbehind = 2000
    , labelHeightGain = 1.0
    , distanceMarkerInterval = Nothing
    , distanceMarkerSegmentEnds = False
    }


defaultCuesheetOptions : CuesheetOptions
defaultCuesheetOptions =
    { totalDistanceDisplay = FromZero
    , referencePoint = 1000
    , itemSpacing = defaultSpacing
    , distanceDetail = defaultDistanceDetail
    , showStartFinish = False
    }


defaultRelativeOptions : RelativeOptions
defaultRelativeOptions =
    { start = AtRoutePosition
    , end = AtWaypoint 0
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
    , position = Nothing
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
    , relative = defaultRelativeOptions
    , offRouteThreshold = 100
    , showOffRouteWaypoints = True
    , showOffRouteDistance = False
    , stateDecodeError = Nothing
    , splitSegments = Nothing
    , profilePixelWidth = Nothing
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
    | AddWaypoint
    | RemoveWaypoint Int
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
    | UpdateSplits Int
    | SetViewMode ViewMode
    | SetSplitMode ActiveSplitMode
    | AddSplitPoint
    | UpdateSplitPoint Int PointRef
    | RemoveSplitPoint Int
    | UpdateLiveLookahead Float
    | UpdateLiveLookbehind Float
    | UpdateDistanceMarkerInterval (Maybe Float)
    | UpdateDistanceMarkerSegmentEnds Bool
    | UpdatePosition (Maybe Float)
      -- Cuesheet
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdateReferencePoint Float
    | UpdateItemSpacing Int
    | UpdateDistanceDetail Int
    | UpdateShowStartFinish Bool
    | UpdateShowOffRouteDistance Bool
    | UpdateSelectedPoint PointRef
    | UpdateOffRouteThreshold Float
    | UpdateShowOffRouteWaypoints Bool
      -- Relative
    | SetRelativeStart PointRef
    | SetRelativeEnd PointRef
      -- State export/import
    | ExportState
    | DownloadSplitsGpx
    | ImportStateFromFile
    | StateFileSelected File.File
    | StateFileRead String
    | ImportStateFromUrl String
    | StateUrlFetched (Result Http.Error String)
    | ProfileWidthChanged Int



-- UPDATE


sortPointRefs : Maybe Float -> EditableTrack -> List PointRef -> List PointRef
sortPointRefs position track =
    List.sortBy (refDistance position track >> Maybe.withDefault 0)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        s =
            model.state

        updateState newState =
            { model | state = newState }

        updateSplitAndStore newModel =
            let
                state =
                    withLiveSplit newModel.state
            in
            ( { newModel | state = state }, Cmd.batch [ storeState (encodeSavedState state), requestSplitCmd state ] )
    in
    case msg of
        Ignore ->
            ( model, Cmd.none )

        DismissStateDecodeError ->
            ( updateState { s | stateDecodeError = Nothing }, Cmd.none )

        ShowOptions show ->
            updateAndStoreModel (updateState { s | showOptions = show })

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
                    updateSplitAndStore
                        (updateState { s | tracks = Error ("parsing result from GPX response: " ++ Json.Decode.errorToString errMsg) })

                Ok typedResult ->
                    case typedResult of
                        Err errMsg ->
                            updateSplitAndStore
                                (updateState { s | tracks = Error ("getting profile data from GPX: " ++ errMsg) })

                        Ok gpxTracks ->
                            updateSplitAndStore
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
                                            { ep | splitPoints = [] }
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
                    updateSplitAndStore (updateState { s | tracks = Loaded (Zipper.navigatePrevious tracks) })

                _ ->
                    ( model, Cmd.none )

        NavigateToNext ->
            case s.tracks of
                Loaded tracks ->
                    updateSplitAndStore (updateState { s | tracks = Loaded (Zipper.navigateNext tracks) })

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

                                nearest =
                                    Location.findNearestTrackPoint gpsPos tracks.current.trackpoints

                                matchedDist =
                                    nearest |> Maybe.map .distance |> Maybe.withDefault 0

                                offRouteDist =
                                    nearest
                                        |> Maybe.map (\tp -> Location.haversineDistance gpsPos (Location.LatLon tp.lat tp.lon))
                                        |> Maybe.withDefault 0
                            in
                            let
                                locatedState =
                                    withLiveSplit
                                        { s
                                            | location = Just (Location.LocationState gpsPos pos.accuracy matchedDist offRouteDist pos.altitude)
                                            , locationError = Nothing
                                            , position = Just matchedDist
                                        }
                            in
                            -- A GPS-derived position is transient, so we never persist it: keeping it
                            -- would mean a stale tracking position is shown when the app is reopened.
                            -- We still store here (with position cleared) to drop any position that was
                            -- previously persisted, so nothing stale survives a reload.
                            ( updateState locatedState
                            , storeState (encodeSavedState { locatedState | position = Nothing })
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
            updateSplitAndStore (updateState <| correctWaypointSelectionInState { s | filteredCategories = newCategories })

        UpdateCategoryFilterEnabled enabled ->
            updateSplitAndStore (updateState <| correctWaypointSelectionInState { s | categoryFilterEnabled = enabled })

        SetAllCategoriesEnabled enabled ->
            updateSplitAndStore (updateState <| correctWaypointSelectionInState { s | filteredCategories = Dict.map (\_ _ -> enabled) s.filteredCategories })

        -- Waypoint editing
        AddWaypoint ->
            case s.tracks of
                Loaded tracks ->
                    let
                        distance =
                            s.position
                                |> Maybe.withDefault 0
                                |> clamp 0 (lastTrackpointDistance tracks.current.trackpoints)

                        ( gain, loss ) =
                            cumulativeGainLossAtDistance distance tracks.current.trackpoints
                                |> Result.withDefault ( 0, 0 )
                    in
                    updateSplitAndStore
                        (updateState
                            { s
                                | tracks =
                                    Loaded <|
                                        Zipper.updateCurrent
                                            (\current ->
                                                { current
                                                    | editableWaypoints =
                                                        current.editableWaypoints
                                                            ++ [ { original =
                                                                    { distance = distance
                                                                    , name = ""
                                                                    , categories = []
                                                                    , gain = gain
                                                                    , loss = loss
                                                                    , offRoute = 0
                                                                    }
                                                                 , deleted = False
                                                                 , created = True
                                                                 , overrides = emptyOverrides
                                                                 }
                                                               ]
                                                }
                                            )
                                            tracks
                            }
                        )

                _ ->
                    ( model, Cmd.none )

        RemoveWaypoint i ->
            updateSplitAndStore (updateState (removeWaypointAt i s))

        WaypointNameChange i name ->
            case s.tracks of
                Loaded tracks ->
                    updateSplitAndStore
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
                    updateSplitAndStore
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
                    updateSplitAndStore
                        (updateState
                            -- A reference to the deleted waypoint no longer resolves, so
                            -- repoint the cuesheet and Relative selections at something that
                            -- does rather than leaving them showing nothing.
                            (correctWaypointSelectionInState
                                { s
                                    | tracks =
                                        Loaded <|
                                            Zipper.updateCurrent
                                                (\current -> updateEditableWaypoint current i (\ew -> { ew | deleted = deleted }))
                                                tracks
                                    , elevationProfile =
                                        { ep
                                            | splitPoints =
                                                if deleted then
                                                    -- remove split point if its waypoint no longer exists
                                                    List.filter ((/=) (AtWaypoint i)) ep.splitPoints

                                                else
                                                    ep.splitPoints
                                        }
                                }
                            )
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
                            List.concatMap effectiveWaypoints (newTracks.prev ++ [ newTracks.current ] ++ newTracks.next)

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
                    updateSplitAndStore
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
                        updateSplitAndStore
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
                    let
                        ep =
                            s.elevationProfile

                        -- Created waypoints are always appended after the source ones,
                        -- so reverting to source keeps source indices 0..sourceCount-1
                        -- intact; only split points aimed at created waypoints are
                        -- now stale. A split at a route position is never stale.
                        sourceCount =
                            List.length (List.filter (not << .created) tracks.current.editableWaypoints)
                    in
                    updateSplitAndStore
                        (updateState
                            (correctWaypointSelectionInState
                                { s
                                    | tracks =
                                        Loaded <|
                                            Zipper.updateCurrent
                                                (\current ->
                                                    { current
                                                        | editableWaypoints =
                                                            current.editableWaypoints
                                                                |> List.filter (not << .created)
                                                                |> List.map (\ew -> { ew | deleted = False, overrides = emptyOverrides })
                                                    }
                                                )
                                                tracks
                                    , elevationProfile =
                                        { ep
                                            | splitPoints =
                                                List.filter
                                                    (\ref ->
                                                        case ref of
                                                            AtWaypoint idx ->
                                                                idx < sourceCount

                                                            AtRoutePosition ->
                                                                True
                                                    )
                                                    ep.splitPoints
                                        }
                                }
                            )
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

        UpdatePosition pos ->
            -- Manually setting or clearing the position drops the GPS fix, whose accuracy no longer applies
            updateSplitAndStore (updateState { s | position = pos, location = Nothing })

        UpdateSplits n ->
            let
                ep =
                    s.elevationProfile
            in
            updateSplitAndStore (updateState { s | elevationProfile = { ep | splitEquidistantCount = n } })

        SetViewMode mode ->
            updateSplitAndStore (updateState { s | viewMode = mode })

        SetSplitMode mode ->
            let
                ep =
                    s.elevationProfile
            in
            updateSplitAndStore (updateState { s | elevationProfile = { ep | activeSplitMode = mode } })

        AddSplitPoint ->
            let
                ep =
                    s.elevationProfile
            in
            case maybeFromloadableResource s.tracks of
                Just tracks ->
                    case
                        selectableSplitPoints s tracks.current
                            |> List.filter (\ref -> not (List.member ref ep.splitPoints))
                            |> List.head
                    of
                        Just ref ->
                            updateSplitAndStore
                                (updateState
                                    { s
                                        | elevationProfile =
                                            { ep | splitPoints = sortPointRefs s.position tracks.current (ref :: ep.splitPoints) }
                                    }
                                )

                        Nothing ->
                            ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        -- splitListPos is a position within the splitPoints list, not a waypoint index.
        UpdateSplitPoint splitListPos newRef ->
            let
                ep =
                    s.elevationProfile

                newPoints =
                    maybeFromloadableResource s.tracks
                        |> Maybe.map
                            (\tracks ->
                                List.Extra.setAt splitListPos newRef ep.splitPoints
                                    |> sortPointRefs s.position tracks.current
                            )
                        |> Maybe.withDefault []
            in
            updateSplitAndStore (updateState { s | elevationProfile = { ep | splitPoints = newPoints } })

        RemoveSplitPoint splitListPos ->
            let
                ep =
                    s.elevationProfile
            in
            updateSplitAndStore
                (updateState { s | elevationProfile = { ep | splitPoints = List.Extra.removeAt splitListPos ep.splitPoints } })

        UpdateLiveLookahead val ->
            let
                ep =
                    s.elevationProfile
            in
            updateSplitAndStore (updateState { s | elevationProfile = { ep | liveLookahead = val } })

        UpdateLiveLookbehind val ->
            let
                ep =
                    s.elevationProfile
            in
            updateSplitAndStore (updateState { s | elevationProfile = { ep | liveLookbehind = val } })

        UpdateDistanceMarkerInterval maybeInterval ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | distanceMarkerInterval = maybeInterval } })

        UpdateDistanceMarkerSegmentEnds show ->
            let
                ep =
                    s.elevationProfile
            in
            updateAndStoreModel (updateState { s | elevationProfile = { ep | distanceMarkerSegmentEnds = show } })

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

        UpdateSelectedPoint ref ->
            let
                cs =
                    s.cuesheet

                newDisplay =
                    case cs.totalDistanceDisplay of
                        ToWaypoint _ ->
                            ToWaypoint ref

                        FromWaypoint _ ->
                            FromWaypoint ref

                        other ->
                            other
            in
            updateAndStoreModel (updateState { s | cuesheet = { cs | totalDistanceDisplay = newDisplay } })

        UpdateOffRouteThreshold threshold ->
            updateAndStoreModel (updateState { s | offRouteThreshold = threshold })

        UpdateShowOffRouteWaypoints show ->
            updateAndStoreModel (updateState { s | showOffRouteWaypoints = show })

        SetRelativeStart ref ->
            let
                rel =
                    s.relative
            in
            updateAndStoreModel (updateState { s | relative = { rel | start = ref } })

        SetRelativeEnd ref ->
            let
                rel =
                    s.relative
            in
            updateAndStoreModel (updateState { s | relative = { rel | end = ref } })

        ExportState ->
            ( model, downloadState (encodeSavedState { s | showOptions = False }) )

        DownloadSplitsGpx ->
            case s.splitSegments of
                Just splitResult ->
                    ( model, requestSplitsGpx (Json.Encode.encode 0 (Json.Encode.list GpxApi.encodeTrack splitResult.segments)) )

                Nothing ->
                    ( model, Cmd.none )

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

        ProfileWidthChanged width ->
            -- Guard against a bad measurement (e.g. the ResizeObserver firing before
            -- #profile-container's layout has settled). A width of 0/1 downsamples the
            -- track line to <2 points and makes it disappear; keep the previous/default
            -- width instead, and log so we can confirm when this happens in the wild.
            if width >= 2 then
                ( updateState { s | profilePixelWidth = Just width }, Cmd.none )

            else
                ( model, logError ("[profile-bug] ignored bad profile width: " ++ String.fromInt width) )


restoreState : String -> Model -> ( Model, Cmd Msg )
restoreState jsonString model =
    case Json.Decode.decodeString stateDecoder jsonString of
        Ok decoded ->
            let
                restored =
                    { model | state = withLiveSplit { decoded | profilePixelWidth = model.state.profilePixelWidth } }
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
    ( model, storeState (encodeSavedState model.state) )


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
                    effectiveWaypoints tracks.current
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
                                                state.elevationProfile.splitPoints
                                                    |> List.filterMap (refDistance state.position tracks.current)
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
                    case state.position of
                        Just p ->
                            ( max 0 (p - ep.liveLookbehind), min maxDist (p + ep.liveLookahead) )

                        Nothing ->
                            ( 0, maxDist )

                segTps =
                    tps |> List.filter (\tp -> tp.distance >= rangeStart && tp.distance <= rangeEnd)

                segWps =
                    effectiveWaypoints tracks.current
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


{-| Physically removes the waypoint at index `i` (used for permanently deleting a
user-created waypoint). Dropping a list element shifts every later index down by
one, so the index-based references into editableWaypoints must be remapped: the
split points, the cuesheet's reference point, the Relative tab's start/end points,
and the transient new-category inputs. correctWaypointSelectionInState then clamps
any selection whose waypoint was the one removed.
-}
removeWaypointAt : Int -> State -> State
removeWaypointAt i s =
    case s.tracks of
        Loaded tracks ->
            let
                ep =
                    s.elevationProfile

                cs =
                    s.cuesheet

                rel =
                    s.relative

                shift idx =
                    if idx > i then
                        idx - 1

                    else
                        idx

                shiftDisplay display =
                    case display of
                        ToWaypoint ref ->
                            ToWaypoint (shiftPointRef i ref)

                        FromWaypoint ref ->
                            FromWaypoint (shiftPointRef i ref)

                        other ->
                            other
            in
            correctWaypointSelectionInState
                { s
                    | tracks =
                        Loaded <|
                            Zipper.updateCurrent
                                (\current -> { current | editableWaypoints = List.Extra.removeAt i current.editableWaypoints })
                                tracks
                    , elevationProfile =
                        { ep | splitPoints = ep.splitPoints |> List.filter ((/=) (AtWaypoint i)) |> List.map (shiftPointRef i) }
                    , cuesheet = { cs | totalDistanceDisplay = shiftDisplay cs.totalDistanceDisplay }
                    , relative =
                        { rel
                            | start = shiftPointRef i rel.start
                            , end = shiftPointRef i rel.end
                        }
                    , newCategoryInputs =
                        s.newCategoryInputs
                            |> Dict.toList
                            |> List.filterMap
                                (\( k, v ) ->
                                    if k == i then
                                        Nothing

                                    else
                                        Just ( shift k, v )
                                )
                            |> Dict.fromList
                }

        _ ->
            s


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


{-| The filters that decide whether a waypoint exists as far as the user is concerned:
category filtering and off-route hiding. Kept separate from the live-view window in
`waypointPredicates` so that flows which pick a waypoint out of the whole route (the
Relative tab) are not limited to the stretch currently on screen.
-}
waypointSelectionPredicates : State -> List (GpxApi.Waypoint -> Bool)
waypointSelectionPredicates state =
    List.filterMap identity
        [ if state.categoryFilterEnabled then
            Just (categoryPredicate state.filteredCategories)

          else
            Nothing
        , if state.showOffRouteWaypoints then
            Nothing

          else
            Just (offRoutePredicate state.offRouteThreshold)
        ]


waypointPredicates : State -> List (GpxApi.Waypoint -> Bool)
waypointPredicates state =
    waypointSelectionPredicates state
        ++ (case ( state.viewMode, state.position ) of
                ( LiveView, Just pos ) ->
                    let
                        ep =
                            state.elevationProfile
                    in
                    [ \wp -> wp.distance >= pos - ep.liveLookbehind && wp.distance <= pos + ep.liveLookahead ]

                _ ->
                    []
           )


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


{-| Pairs each waypoint that survived filtering with the index a `PointRef` would name it by,
so a selector's options carry references the rest of the app can resolve. See `PointRef` for
why that is the `editableWaypoints` index rather than a position in this list.
-}
indexedFilteredWaypoints : EditableTrack -> List GpxApi.Waypoint -> List ( Int, GpxApi.Waypoint )
indexedFilteredWaypoints track filtered =
    track.editableWaypoints
        |> List.indexedMap Tuple.pair
        |> List.filter (Tuple.second >> .deleted >> not)
        |> List.map (Tuple.mapSecond (effectiveWaypoint track.trackpoints))
        |> List.filter (\( _, wp ) -> List.member wp filtered)


{-| The waypoints offered for selection to the flows that pick a point out of the whole
route — the Relative tab and the elevation profile's split boundaries.

Deliberately filtered by `waypointSelectionPredicates` rather than the full
`waypointPredicates`: a selection must not disappear just because the live-view window has
moved past the waypoint it names.

-}
selectableWaypoints : State -> EditableTrack -> List ( Int, GpxApi.Waypoint )
selectableWaypoints state track =
    indexedFilteredWaypoints track
        (filterWaypoints (waypointSelectionPredicates state) (effectiveWaypoints track))


{-| The points the elevation profile offers as split boundaries. Waypoints come first so
that "Add" keeps working through them in route order before reaching for the position.
-}
selectableSplitPoints : State -> EditableTrack -> List PointRef
selectableSplitPoints state track =
    List.map (Tuple.first >> AtWaypoint) (selectableWaypoints state track)
        ++ positionRefIfSet state


{-| `AtRoutePosition` as a one-element list when a position is set, so selector option
lists can simply append it.
-}
positionRefIfSet : State -> List PointRef
positionRefIfSet state =
    case state.position of
        Just _ ->
            [ AtRoutePosition ]

        Nothing ->
            []


{-| Repoints a display mode whose reference waypoint has been filtered away or deleted. A
route position is never filtered away, so it is always left alone.
-}
correctWaypointSelection : TotalDistanceDisplay -> List ( Int, GpxApi.Waypoint ) -> TotalDistanceDisplay
correctWaypointSelection display indexed =
    let
        isSelectable ref =
            case ref of
                AtWaypoint idx ->
                    List.any (\( i, _ ) -> i == idx) indexed

                AtRoutePosition ->
                    True

        correct rebuild fallback ref =
            if isSelectable ref then
                display

            else
                case fallback indexed of
                    Just ( fallbackIdx, _ ) ->
                        rebuild (AtWaypoint fallbackIdx)

                    Nothing ->
                        display
    in
    case display of
        ToWaypoint ref ->
            correct ToWaypoint List.Extra.last ref

        FromWaypoint ref ->
            correct FromWaypoint List.head ref

        _ ->
            display


{-| The point the current display mode measures to or from, resolved for the modes that have
one. Shared by the cuesheet and the elevation profile's distance markers.
-}
referenceWaypoint : State -> EditableTrack -> Maybe GpxApi.Waypoint
referenceWaypoint state track =
    case state.cuesheet.totalDistanceDisplay of
        ToWaypoint ref ->
            resolvePointRef state.position state.location track ref

        FromWaypoint ref ->
            resolvePointRef state.position state.location track ref

        _ ->
            Nothing


correctWaypointSelectionInState : State -> State
correctWaypointSelectionInState s =
    case maybeFromloadableResource s.tracks of
        Nothing ->
            s

        Just tracks ->
            let
                indexed =
                    indexedFilteredWaypoints tracks.current
                        (filterWaypoints (waypointPredicates s) (effectiveWaypoints tracks.current))

                cs =
                    s.cuesheet

                corrected =
                    correctWaypointSelection cs.totalDistanceDisplay indexed

                rel =
                    s.relative

                -- The Relative tab can target waypoints outside the live window, so its
                -- selection is validated against its own, wider list.
                relativeSelectable =
                    selectableWaypoints s tracks.current

                clampToSelectable fallback ref =
                    case ref of
                        -- The position is always available, whatever the waypoint filters do
                        AtRoutePosition ->
                            ref

                        AtWaypoint idx ->
                            if List.any (\( i, _ ) -> i == idx) relativeSelectable then
                                ref

                            else
                                fallback relativeSelectable
                                    |> Maybe.map (Tuple.first >> AtWaypoint)
                                    |> Maybe.withDefault ref
            in
            { s
                | cuesheet = { cs | totalDistanceDisplay = corrected }
                , relative =
                    { rel
                        | start = clampToSelectable List.head rel.start
                        , end = clampToSelectable List.Extra.last rel.end
                    }
            }


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

                                    RelativeTab ->
                                        viewRelativeTab state tracks
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
            , Html.Attributes.style "border-radius" "0"
            , if activeTab == WaypointsTab then
                Html.Attributes.style "font-weight" "bold"

              else
                Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text "Waypoints" ]
        , Html.button
            [ Html.Events.onClick (SwitchTab RelativeTab)
            , Html.Attributes.class "button-4"
            , Html.Attributes.style "border-radius" "0 4px 4px 0"
            , if activeTab == RelativeTab then
                Html.Attributes.style "font-weight" "bold"

              else
                Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text "Relative" ]
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

        -- distance markers reuse the cuesheet's "Total distance" setting so distance
        -- reads the same in both views
        cs =
            state.cuesheet

        currentFinishDistance =
            lastTrackpointDistance tracks.current.trackpoints

        refWaypoint =
            referenceWaypoint state tracks.current
    in
    case state.splitSegments of
        Nothing ->
            Html.text ""

        Just splitResult ->
            let
                downsampleWidth =
                    Maybe.withDefault profileSvgWidth state.profilePixelWidth

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
                                        state.position
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
                                            |> downsample downsampleWidth

                                    downsampledSeg =
                                        { seg | trackpoints = downsample downsampleWidth seg.trackpoints }

                                    markers =
                                        distanceMarkers
                                            { mode = cs.totalDistanceDisplay
                                            , finishDist = currentFinishDistance
                                            , referencePoint = cs.referencePoint
                                            , refWaypoint = refWaypoint
                                            , detail = cs.distanceDetail
                                            , interval = ep.distanceMarkerInterval
                                            , segmentEnds = ep.distanceMarkerSegmentEnds
                                            , segStart = segStart
                                            , segMaxDistance = segMaxDistance
                                            }
                                in
                                profile segIndex downsampledSeg seg.trackpoints segMaxDistance trackMinElevation trackMaxElevation ep.fontSize ep.trackHeight ep.trackThickness ep.labelHeightGain state.offRouteThreshold segPosition segIntensity trackMinIntensity trackMaxIntensity markers
                            )
            in
            Html.div []
                [ liveNoPositionWarning state
                , Html.div [ Html.Attributes.id profileContainerId ] profileViews
                ]


profileContainerId : String
profileContainerId =
    "profile-container"


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


{-| The distance value to display for an absolute route distance, given the chosen
display mode. Returns Nothing when nothing should be shown (None, or an unresolved
reference waypoint). Shared by the cuesheet and the elevation profile distance markers.
-}
displayedDistanceValue : TotalDistanceDisplay -> Float -> Float -> Maybe GpxApi.Waypoint -> Float -> Maybe Float
displayedDistanceValue mode finishDist referencePoint refWaypoint distance =
    case mode of
        None ->
            Nothing

        FromZero ->
            Just distance

        ToFinish ->
            Just (finishDist - distance)

        ToPoint ->
            Just (referencePoint - distance)

        ToWaypoint _ ->
            refWaypoint |> Maybe.map (\rw -> rw.distance - distance)

        FromWaypoint _ ->
            refWaypoint |> Maybe.map (\rw -> distance - rw.distance)

        PercentProgress ->
            safePercent distance finishDist

        PercentRemaining ->
            safePercent (finishDist - distance) finishDist


{-| True for the percentage display modes, whose distance/elevation values are fractions of
the route total rather than absolute metres. The single switch the formatting code keys off.
-}
displayIsPercent : TotalDistanceDisplay -> Bool
displayIsPercent mode =
    case mode of
        PercentProgress ->
            True

        PercentRemaining ->
            True

        _ ->
            False


{-| `part` as a percentage of `total`, or Nothing when `total` is non-positive (empty or
flat route) so we never display NaN.
-}
safePercent : Float -> Float -> Maybe Float
safePercent part total =
    if total > 0 then
        Just (part / total * 100)

    else
        Nothing


{-| A "nice" round marker interval (in metres) for a displayed-distance range (in metres),
bucketed like elevationTicks.
-}
niceDistanceInterval : Float -> Float
niceDistanceInterval range =
    if range > 100000 then
        20000

    else if range > 50000 then
        10000

    else if range > 20000 then
        5000

    else if range > 10000 then
        2000

    else
        1000


{-| A "nice" round marker interval (in %) for a displayed-percentage range, mirroring
`niceDistanceInterval` but bucketed for the 0–100 scale of the percentage display modes.
-}
nicePercentInterval : Float -> Float
nicePercentInterval range =
    if range > 50 then
        25

    else if range > 20 then
        10

    else if range > 10 then
        5

    else if range > 5 then
        2

    else
        1


{-| Evenly-spaced, round-numbered distance markers for one profile segment. Each mode is a
linear map of absolute distance (value = base ± distance), so ticks are placed at multiples
of the interval in the displayed metric and inverted back to a segment-local position. The
returned distance is segment-local (metres), ready for the segment's XYCalculator.
-}
distanceMarkers :
    { mode : TotalDistanceDisplay
    , finishDist : Float
    , referencePoint : Float
    , refWaypoint : Maybe GpxApi.Waypoint
    , detail : Int
    , interval : Maybe Float
    , segmentEnds : Bool
    , segStart : Float
    , segMaxDistance : Float
    }
    -> List { distance : Float, label : String }
distanceMarkers cfg =
    let
        displayed dist =
            displayedDistanceValue cfg.mode cfg.finishDist cfg.referencePoint cfg.refWaypoint dist
    in
    case ( displayed cfg.segStart, displayed (cfg.segStart + cfg.segMaxDistance) ) of
        ( Just vStart, Just vEnd ) ->
            let
                ( vMin, vMax ) =
                    ( min vStart vEnd, max vStart vEnd )

                isPercent =
                    displayIsPercent cfg.mode

                interval =
                    if isPercent then
                        -- cfg.interval is a metres setting, meaningless on the % scale, so
                        -- always auto-pick a round % interval here.
                        nicePercentInterval (vMax - vMin)

                    else
                        Maybe.withDefault (niceDistanceInterval (vMax - vMin)) cfg.interval

                firstTick =
                    toFloat (ceiling (vMin / interval)) * interval

                buildValues current acc =
                    if current > vMax then
                        List.reverse acc

                    else
                        buildValues (current + interval) (current :: acc)

                -- The displayed value is a linear map of distance: ±1 per metre for the
                -- distance modes, ±(100/finishDist) per metre for the percentage modes, so a
                -- displayed-value offset converts to a segment-local distance (metres) by
                -- scaling with metresPerDisplayedUnit.
                metresPerDisplayedUnit =
                    if isPercent then
                        cfg.finishDist / 100

                    else
                        1

                toMarker value =
                    { distance =
                        (if vStart <= vEnd then
                            value - vStart

                         else
                            vStart - value
                        )
                            * metresPerDisplayedUnit
                    , label =
                        if isPercent then
                            formatPercent value

                        else
                            formatKm cfg.detail value
                    }

                segmentEndValues =
                    if cfg.segmentEnds then
                        [ vStart, vEnd ]

                    else
                        []
            in
            (buildValues firstTick [] ++ segmentEndValues)
                |> List.map toMarker
                |> List.Extra.uniqueBy (.distance >> round)

        _ ->
            []


profile : Int -> GpxApi.Track -> List GpxApi.TrackPoint -> Float -> Float -> Float -> Float -> Int -> Float -> Float -> Float -> Maybe Float -> List { distance : Float, intensity : Float } -> Float -> Float -> List { distance : Float, label : String } -> Html Msg
profile segmentIndex track fullTrackpoints maxDistance minElevation maxElevation fontSize trackHeight trackThickness labelHeightGain offRouteThreshold maybePosition intensityPoints minIntensity maxIntensity markers =
    let
        waypointTextHeight =
            track.waypoints
                |> List.map (\w -> String.length w.name)
                |> List.maximum
                |> Maybe.withDefault 0
                |> (\len -> max 100 (round (toFloat len * 0.6 * fontSize * labelHeightGain)))

        -- a reserved row below the axis for horizontal distance-marker labels, so they
        -- don't collide with the rotated waypoint names
        markerLabelHeight =
            if List.isEmpty markers then
                0

            else
                14

        svgHeight =
            trackHeight + markerLabelHeight + waypointTextHeight

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
            , -- distance markers
              Svg.g []
                (markers
                    |> List.concatMap
                        (\marker ->
                            let
                                x =
                                    calc.x marker.distance
                            in
                            [ Svg.line
                                [ Svg.Attributes.x1 x
                                , Svg.Attributes.y1 <| String.fromInt <| trackHeight - 4
                                , Svg.Attributes.x2 x
                                , Svg.Attributes.y2 <| String.fromInt <| trackHeight + 4
                                , Svg.Attributes.stroke "grey"
                                , Svg.Attributes.strokeWidth "1"
                                ]
                                []
                            , Svg.text_
                                [ Svg.Attributes.x x
                                , Svg.Attributes.y <| String.fromInt <| trackHeight + markerLabelHeight - 3
                                , Svg.Attributes.textAnchor "middle"
                                , Svg.Attributes.fontSize "10"
                                , Svg.Attributes.fill "grey"
                                ]
                                [ Svg.text marker.label ]
                            ]
                        )
                )
            , -- waypoints
              Svg.g []
                (let
                    svgBottom =
                        String.fromInt svgHeight

                    paddedWaypointTextY =
                        String.fromInt <| trackHeight + 5 + markerLabelHeight
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
                                        offRouteColour

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
    -- maxPoints < 2 can't produce a drawable line (the stride maths divides by zero
    -- and yields 0/1 points), so keep the full list rather than blanking the track.
    if maxPoints < 2 || len <= maxPoints then
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
            effectiveWaypoints tracks.current

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
            resolvePointRef state.position state.location tracks.current AtRoutePosition

        -- Sort by distance so edited waypoint distances reorder the list (the original
        -- waypoint order no longer matches distance once a distance override is applied)
        waypointsWithPosition =
            List.sortBy .distance
                (case positionWaypoint of
                    Just pw ->
                        pw :: filteredWaypoints

                    Nothing ->
                        filteredWaypoints
                )

        -- Live view trims the list to what's ahead of the position; static view shows the whole list with the marker inline
        scrollPosition =
            case state.viewMode of
                LiveView ->
                    Maybe.withDefault 0 state.position

                StaticView ->
                    0

        refWaypoint =
            referenceWaypoint state tracks.current

        refPointEle =
            case refWaypoint of
                Just wp ->
                    ( wp.gain, wp.loss )

                Nothing ->
                    cumulativeGainLossAtDistance cs.referencePoint tracks.current.trackpoints
                        |> Result.withDefault ( 0, 0 )
    in
    Html.div []
        [ liveNoPositionWarning state
        , cuesheetSvg state.offRouteThreshold state.showOffRouteDistance (Maybe.map .distance positionWaypoint) scrollPosition waypointsWithPosition cs currentFinishDistance tracks.current.gainLoss refPointEle refWaypoint
        ]


viewWaypointsTab : State -> Zipper EditableTrack -> Html Msg
viewWaypointsTab state tracks =
    let
        maxDistance =
            lastTrackpointDistance tracks.current.trackpoints

        anyWaypointEdited =
            List.any
                (\ew -> ew.deleted || ew.created || ew.overrides /= emptyOverrides)
                tracks.current.editableWaypoints
    in
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.5em"
        , Html.Attributes.style "padding" "0.5em"
        ]
        [ viewButton [] "Add waypoint" AddWaypoint
        , if anyWaypointEdited then
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
                                effectiveWaypoint tracks.current.trackpoints ew

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
                                        , if ew.created then
                                            viewButton [] "X" (RemoveWaypoint i)

                                          else
                                            viewButton [] "X" (WaypointDeleted i True)
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


cuesheetSvg : Float -> Bool -> Maybe Float -> Float -> List GpxApi.Waypoint -> CuesheetOptions -> Float -> ( Float, Float ) -> ( Float, Float ) -> Maybe GpxApi.Waypoint -> Html Msg
cuesheetSvg offRouteThreshold showOffRouteDistance positionDistance scrollPosition waypoints cs finishDist ( totalGain, totalLoss ) refPointEle refWaypoint =
    let
        info =
            waypointInfos positionDistance scrollPosition waypoints

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
                            renderWaypointItem showOffRoute fillAttrs waypoint =
                                let
                                    displayedDistance =
                                        displayedDistanceValue cs.totalDistanceDisplay finishDist cs.referencePoint refWaypoint waypoint.distance

                                    -- This waypoint is the point the total distance is measured to/from,
                                    -- so its to/from distance and elevation are both 0 and not worth showing.
                                    isReferencePoint =
                                        displayedDistance == Just 0

                                    waypointDistance =
                                        if isReferencePoint then
                                            Nothing

                                        else if displayIsPercent cs.totalDistanceDisplay then
                                            Maybe.map formatPercent displayedDistance

                                        else
                                            Maybe.map (formatKm cs.distanceDetail) displayedDistance

                                    waypointEle =
                                        if isReferencePoint then
                                            Nothing

                                        else
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

                                                PercentProgress ->
                                                    Maybe.map2 formatEleGainLossPercent
                                                        (safePercent waypoint.gain totalGain)
                                                        (safePercent waypoint.loss totalLoss)

                                                PercentRemaining ->
                                                    Maybe.map2 formatEleGainLossPercent
                                                        (safePercent (totalGain - waypoint.gain) totalGain)
                                                        (safePercent (totalLoss - waypoint.loss) totalLoss)

                                    offRouteLabel =
                                        String.fromInt (round waypoint.offRoute) ++ "m off"

                                    waypointInfo =
                                        List.filterMap identity
                                            [ waypointDistance |> Maybe.map (\s -> ( s, [] ))
                                            , waypointEle |> Maybe.map (\s -> ( s, [] ))
                                            , case waypoint.categories of
                                                [] ->
                                                    Nothing

                                                cats ->
                                                    Just ( String.join ", " cats, [] )
                                            , if waypoint.offRoute > offRouteThreshold then
                                                Just ( "⚠️ " ++ offRouteLabel, [ Svg.Attributes.fill offRouteColour ] )

                                              else if showOffRoute && waypoint.offRoute > 0 then
                                                Just ( offRouteLabel, [] )

                                              else
                                                Nothing
                                            ]

                                    waypointInfoLines =
                                        if List.isEmpty waypointInfo then
                                            [ ( "◉", [] ) ]

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
                                                    (\j ( line, lineAttributes ) ->
                                                        Svg.text_
                                                            ([ Svg.Attributes.x svgContentLeftStartString
                                                             , Svg.Attributes.y <| String.fromInt (cs.itemSpacing // 2)
                                                             , Svg.Attributes.dominantBaseline "middle"
                                                             , Svg.Attributes.dy (String.fromFloat (toFloat j - (toFloat <| List.length waypointInfoLines - 1) / 2) ++ "em")
                                                             , Svg.Attributes.textAnchor "end"
                                                             , Svg.Attributes.fontSize "smaller"
                                                             ]
                                                                ++ lineAttributes
                                                            )
                                                            [ Svg.text line ]
                                                    )
                                           )
                                    )
                        in
                        case item of
                            InfoWaypoint waypoint ->
                                renderWaypointItem showOffRouteDistance
                                    (if waypoint.offRoute > offRouteThreshold then
                                        [ Svg.Attributes.fill offRouteColour ]

                                     else
                                        []
                                    )
                                    waypoint

                            InfoPosition waypoint ->
                                renderWaypointItem True [ Svg.Attributes.fill "steelblue" ] waypoint

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
                                            if displayIsPercent cs.totalDistanceDisplay then
                                                (safePercent dist finishDist |> Maybe.map formatPercent |> Maybe.withDefault "")
                                                    ++ " "
                                                    ++ formatEleGainLossPercent
                                                        (safePercent gain totalGain |> Maybe.withDefault 0)
                                                        (safePercent loss totalLoss |> Maybe.withDefault 0)

                                            else
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


-- RELATIVE VIEW


{-| One end of the Relative tab's comparison: the waypoint it stands for, plus where that
actually is in the world.

`coordsFromGps` / `elevationFromGps` record whether each came from a real fix or was read off
the route, so the view can say which — the two disagree whenever the rider is off route, and
a figure whose origin is invisible is a figure that misleads.

-}
type alias RelativePoint =
    { waypoint : GpxApi.Waypoint
    , latLon : Location.LatLon
    , elevation : Float
    , coordsFromGps : Bool
    , elevationFromGps : Bool
    }


{-| Places a resolved waypoint in the world. A GPS fix locates the rider exactly, so it wins
when there is one; everything else is read off the trackpoint the point's route distance
lands on.

That fallback is the only option for a waypoint: `GpxApi.Waypoint` is distance, name,
categories, gain, loss and off-route distance, with no coordinates of its own. So an
off-route waypoint resolves to its matched point on the route and the direct figures reach
there rather than the waypoint itself — `snapNote` reports that gap rather than glossing it.

-}
relativePointFor : List GpxApi.TrackPoint -> Maybe Location.LocationState -> GpxApi.Waypoint -> Maybe RelativePoint
relativePointFor trackpoints fix waypoint =
    trackpointAtDistance waypoint.distance trackpoints
        |> Maybe.map
            (\tp ->
                { waypoint = waypoint
                , latLon = fix |> Maybe.map .position |> Maybe.withDefault (Location.LatLon tp.lat tp.lon)
                , elevation = fix |> Maybe.andThen .altitude |> Maybe.withDefault tp.elevation
                , coordsFromGps = fix /= Nothing
                , elevationFromGps = (fix |> Maybe.andThen .altitude) /= Nothing
                }
            )


viewRelativeTab : State -> Zipper EditableTrack -> Html Msg
viewRelativeTab state tracks =
    let
        rel =
            state.relative

        selectable =
            selectableWaypoints state tracks.current

        -- Resolved through `selectable` rather than the whole track, so a reference to a
        -- waypoint the filters have hidden reads as "nothing chosen" instead of silently
        -- comparing against something that is not in the dropdown.
        waypointFor ref =
            case ref of
                AtWaypoint idx ->
                    selectable |> List.Extra.find (\( i, _ ) -> i == idx) |> Maybe.map Tuple.second

                AtRoutePosition ->
                    resolvePointRef state.position state.location tracks.current AtRoutePosition

        pointFor ref =
            waypointFor ref
                |> Maybe.andThen
                    (relativePointFor tracks.current.trackpoints
                        (case ref of
                            -- A stored location can only belong to the position, because
                            -- setting the position by hand clears it (see UpdatePosition) —
                            -- and a hand-set position is only ever a route distance, so it
                            -- offers no fix and reads off the route.
                            AtRoutePosition ->
                                state.location

                            AtWaypoint _ ->
                                Nothing
                        )
                    )

        unresolvedNotice ref fallback =
            case ref of
                AtRoutePosition ->
                    "This needs a position on the route. Set one with the Position slider in the options panel, or start tracking."

                AtWaypoint _ ->
                    fallback

        contextCardOrNotice role fallback ref =
            case pointFor ref of
                Just point ->
                    viewRelativeContextCard tracks.current role point

                Nothing ->
                    relativeNotice (unresolvedNotice ref fallback)

        body =
            if List.isEmpty selectable then
                [ relativeNotice "No waypoints to compare. Add one in the Waypoints tab, or check the waypoint category filter in the options panel." ]

            else
                List.concat
                    [ [ contextCardOrNotice "Start" "Choose a start point." rel.start ]

                    -- Only travel between two points that both resolve; the notices in
                    -- their place say which one still needs choosing.
                    , case Maybe.map2 Tuple.pair (pointFor rel.start) (pointFor rel.end) of
                        Just ( startPoint, endPoint ) ->
                            [ viewRelativeTravelCard tracks.current selectable startPoint endPoint ]

                        Nothing ->
                            []
                    , [ contextCardOrNotice "End" "Choose an end point." rel.end ]
                    ]
    in
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.75em"
        , Html.Attributes.style "padding" "0.5em"
        ]
        (viewRelativeControls (state.position /= Nothing) rel selectable :: body)


viewRelativeControls : Bool -> RelativeOptions -> List ( Int, GpxApi.Waypoint ) -> Html Msg
viewRelativeControls hasPosition rel selectable =
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-wrap" "wrap"
        , Html.Attributes.style "gap" "1em"
        , Html.Attributes.style "align-items" "flex-end"
        ]
        [ relativeControl "Start" (viewPointSelector { onSelect = SetRelativeStart, hasPosition = hasPosition } selectable rel.start)
        , relativeControl "End" (viewPointSelector { onSelect = SetRelativeEnd, hasPosition = hasPosition } selectable rel.end)
        ]


{-| Where one end of the comparison sits on the route, under a heading naming the role it
plays ("Start" / "End") so the two cards either side of the travel figures are told apart at
a glance. Built from the resolved point, so a route position — which `resolvePointRef` hands
back as a synthetic waypoint — reads exactly like a chosen waypoint, and the elevation shown
is the same one the travel figures were computed from.
-}
viewRelativeContextCard : EditableTrack -> String -> RelativePoint -> Html Msg
viewRelativeContextCard track role point =
    let
        waypoint =
            point.waypoint

        ( totalGain, totalLoss ) =
            track.gainLoss
    in
    relativeCard role
        (List.filterMap identity
            [ Just (Html.div [ Html.Attributes.style "font-weight" "bold" ] [ Html.text (waypointDisplayName waypoint) ])
            , snapNote point
                |> Maybe.map
                    (\note ->
                        Html.div
                            [ Html.Attributes.style "font-size" "0.85em"
                            , Html.Attributes.style "opacity" "0.7"
                            , Html.Attributes.style "font-style" "italic"
                            ]
                            [ Html.text note ]
                    )
            , case waypoint.categories of
                [] ->
                    Nothing

                categories ->
                    Just (relativeRow "Categories" (String.join ", " categories))
            , Just (relativeRow (elevationLabel point.elevationFromGps) (formatM point.elevation))
            , Just (relativeRow "From start" (formatKm 1 waypoint.distance ++ " · " ++ formatEleGainLoss waypoint.gain waypoint.loss))
            , Just
                (relativeRow "To finish"
                    (formatKm 1 (lastTrackpointDistance track.trackpoints - waypoint.distance)
                        ++ " · "
                        ++ formatEleGainLoss (totalGain - waypoint.gain) (totalLoss - waypoint.loss)
                    )
                )
            ]
        )


{-| Names the gap between where the point really is and the route point its figures were read
at. Both a GPS fix and an off-route waypoint sit beside the route rather than on it, so both
get the same treatment; a point already on the route has no gap to report.

This replaces a plain "off route" row: the distance is the same number, but what matters is
not that the point is off the route, it is that everything else on the card was measured
somewhere else.

-}
snapNote : RelativePoint -> Maybe String
snapNote point =
    if point.waypoint.offRoute > 0 then
        Just
            ("nearest route point to "
                ++ (if point.coordsFromGps then
                        "your fix"

                    else
                        "the waypoint"
                   )
                ++ ", "
                ++ formatM point.waypoint.offRoute
                ++ " away"
            )

    else
        Nothing


elevationLabel : Bool -> String
elevationLabel fromGps =
    if fromGps then
        "Elevation (GPS)"

    else
        "Elevation"


{-| What it takes to get from the start point to the end point, both ways of measuring it:
straight there, and following the route.
-}
viewRelativeTravelCard : EditableTrack -> List ( Int, GpxApi.Waypoint ) -> RelativePoint -> RelativePoint -> Html Msg
viewRelativeTravelCard track selectable start end =
    let
        crowFlies =
            Location.haversineDistance start.latLon end.latLon

        elevationDifference =
            end.elevation - start.elevation

        alongRoute =
            end.waypoint.distance - start.waypoint.distance

        -- Travelling from start to end against the route's direction turns its climbs into
        -- descents and its descents into climbs
        ( gain, loss ) =
            if alongRoute < 0 then
                ( start.waypoint.loss - end.waypoint.loss, start.waypoint.gain - end.waypoint.gain )

            else
                ( end.waypoint.gain - start.waypoint.gain, end.waypoint.loss - start.waypoint.loss )

        usingFix =
            start.coordsFromGps || end.coordsFromGps

        waypointsBetween =
            selectable
                |> List.filter
                    (\( _, wp ) ->
                        wp.distance
                            > min start.waypoint.distance end.waypoint.distance
                            && wp.distance
                            < max start.waypoint.distance end.waypoint.distance
                    )
                |> List.length
    in
    relativeCard "Travel"
        [ relativeSection "Direct"
            (if usingFix then
                "from your GPS fix"

             else
                "between points on the route"
            )
            (List.filterMap identity
                [ Just (relativeRow "Distance" (formatKm 2 crowFlies))
                , Just (relativeRow "Bearing" (formatBearing (Location.bearing start.latLon end.latLon)))
                , Just (relativeRow (elevationLabel (start.elevationFromGps || end.elevationFromGps)) (formatSignedM elevationDifference))
                , if crowFlies > 0 then
                    Just (relativeRow "Gradient" (formatGradient (elevationDifference / crowFlies * 100)))

                  else
                    Nothing
                ]
            )
        , relativeSection "Along route"
            -- Only the route can say how far along it something is, so a GPS fix has to be
            -- taken as the route point it matched — worth saying when the two differ.
            (if usingFix then
                "your position taken as the nearest route point"

             else
                ""
            )
            (List.filterMap identity
                [ Just
                    (relativeRow "Distance"
                        (formatSignedKm 1 alongRoute
                            ++ (if alongRoute < 0 then
                                    " (behind you)"

                                else
                                    ""
                               )
                        )
                    )
                , Just (relativeRow "Climb" (formatEleGainLoss gain loss))
                , if alongRoute /= 0 then
                    Just (relativeRow "Climbing rate" (formatClimbRate (gain / abs alongRoute * 1000)))

                  else
                    Nothing
                , Maybe.map2
                    (\distanceShare climbShare ->
                        relativeRow "Share of route" (formatPercent distanceShare ++ " of distance · " ++ formatPercent climbShare ++ " of climbing")
                    )
                    (safePercent (abs alongRoute) (lastTrackpointDistance track.trackpoints))
                    -- Riding a segment backwards climbs what the route descends, so the
                    -- share is against the route's total descent to compare like with like
                    (safePercent gain
                        (if alongRoute < 0 then
                            Tuple.second track.gainLoss

                         else
                            Tuple.first track.gainLoss
                        )
                    )
                , Just (relativeRow "Waypoints between" (String.fromInt waypointsBetween))
                ]
            )
        ]


relativeNotice : String -> Html Msg
relativeNotice text =
    Html.div [ Html.Attributes.class "warning_panel" ] [ Html.text text ]


relativeControl : String -> Html Msg -> Html Msg
relativeControl label control =
    Html.label
        [ Html.Attributes.style "display" "inline-flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.2em"
        ]
        [ Html.span
            [ Html.Attributes.style "font-size" "0.85em"
            , Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text label ]
        , control
        ]


relativeCard : String -> List (Html Msg) -> Html Msg
relativeCard title contents =
    Html.div
        [ Html.Attributes.style "border" "1px solid #ddd"
        , Html.Attributes.style "border-radius" "6px"
        , Html.Attributes.style "padding" "0.5em 0.75em"
        , Html.Attributes.style "background" "#fafafa"
        , Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.5em"
        ]
        (Html.h3 [ Html.Attributes.style "margin" "0" ] [ Html.text title ] :: contents)


{-| A titled group of rows. `note` says where the section's figures were measured from, and
is empty when there is nothing to disambiguate.
-}
relativeSection : String -> String -> List (Html Msg) -> Html Msg
relativeSection title note rows =
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.15em"
        ]
        (Html.div
            [ Html.Attributes.style "font-size" "0.85em"
            , Html.Attributes.style "opacity" "0.7"
            , Html.Attributes.style "border-bottom" "1px solid #ddd"
            , Html.Attributes.style "display" "flex"
            , Html.Attributes.style "flex-wrap" "wrap"
            , Html.Attributes.style "gap" "0.5em"
            , Html.Attributes.style "justify-content" "space-between"
            ]
            [ Html.text title
            , Html.span [ Html.Attributes.style "font-style" "italic" ] [ Html.text note ]
            ]
            :: rows
        )


relativeRow : String -> String -> Html Msg
relativeRow label value =
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-wrap" "wrap"
        , Html.Attributes.style "gap" "0.5em"
        , Html.Attributes.style "justify-content" "space-between"
        ]
        [ Html.span [ Html.Attributes.style "opacity" "0.7" ] [ Html.text label ]
        , Html.span [] [ Html.text value ]
        ]


formatKm : Int -> Float -> String
formatKm decimalPlaces metres =
    Round.round decimalPlaces (metres / 1000) ++ "km"


formatM : Float -> String
formatM metres =
    Round.round 0 metres ++ "m"


formatEleGainLoss : Float -> Float -> String
formatEleGainLoss gain loss =
    "↑" ++ formatM gain ++ " ↓" ++ formatM loss


formatPercent : Float -> String
formatPercent pct =
    Round.round 0 pct ++ "%"


formatEleGainLossPercent : Float -> Float -> String
formatEleGainLossPercent gainPct lossPct =
    "↑" ++ formatPercent gainPct ++ " ↓" ++ formatPercent lossPct


{-| Signs a formatted value so a reader can tell "132m higher" from "132m lower" at a
glance. Round to the displayed precision first, so a value that displays as zero is not
given a misleading sign.
-}
withSign : (Float -> String) -> Float -> String
withSign format value =
    if value > 0 then
        "+" ++ format value

    else
        format value


formatSignedM : Float -> String
formatSignedM =
    withSign formatM << roundTo 0


formatSignedKm : Int -> Float -> String
formatSignedKm decimalPlaces =
    roundTo (decimalPlaces - 3) >> withSign (formatKm decimalPlaces)


formatGradient : Float -> String
formatGradient =
    roundTo 1 >> withSign (\pct -> Round.round 1 pct ++ "%")


formatClimbRate : Float -> String
formatClimbRate metresPerKm =
    Round.round 0 metresPerKm ++ "m/km"


roundTo : Int -> Float -> Float
roundTo decimalPlaces value =
    let
        factor =
            10 ^ toFloat decimalPlaces
    in
    toFloat (round (value * factor)) / factor


{-| Compass bearing as degrees plus the nearest of the 16 compass points, e.g. "143° (SE)".
-}
formatBearing : Float -> String
formatBearing degreesFromNorth =
    let
        points =
            [ "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" ]

        point =
            List.Extra.getAt (modBy 16 (round (degreesFromNorth / 22.5))) points
                |> Maybe.withDefault "N"
    in
    Round.round 0 degreesFromNorth ++ "° (" ++ point ++ ")"


{-| The first trackpoint at or beyond `dist`, falling back to the last trackpoint for a
distance past the end of the route. Nothing only when the track has no points at all.

TODO: interpolate between bracketing trackpoints when dist falls between two points,
rather than snapping to the next one (could use interpolateTrackpointAt)

-}
trackpointAtDistance : Float -> List GpxApi.TrackPoint -> Maybe GpxApi.TrackPoint
trackpointAtDistance dist trackpoints =
    case List.Extra.find (\tp -> tp.distance >= dist) trackpoints of
        Just tp ->
            Just tp

        Nothing ->
            List.Extra.last trackpoints


cumulativeGainLossAtDistance : Float -> List GpxApi.TrackPoint -> Result String ( Float, Float )
cumulativeGainLossAtDistance dist trackpoints =
    trackpointAtDistance dist trackpoints
        |> Maybe.map (\tp -> Ok ( tp.gain, tp.loss ))
        |> Maybe.withDefault (Err "no trackpoints found for gain/loss lookup")



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
                            case state.splitSegments of
                                Just _ ->
                                    [ viewButton [] "Download splits" DownloadSplitsGpx ]

                                Nothing ->
                                    []

                    -- Tab-specific options
                    , case state.activeTab of
                        ElevationProfileTab ->
                            viewElevationProfileOptions state

                        CuesheetTab ->
                            viewCuesheetOptionsPanel state

                        WaypointsTab ->
                            []

                        -- The Relative tab's controls live in the tab itself, beside the
                        -- figures they drive.
                        RelativeTab ->
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
                        selectable =
                            maybeFromloadableResource state.tracks
                                |> Maybe.map (.current >> selectableWaypoints state)
                                |> Maybe.withDefault []

                        availableCount =
                            List.length selectable + List.length (positionRefIfSet state)

                        -- splitListPos is a position in the splits list, not a waypoint index
                        dropdownRow splitListPos selectedRef =
                            Html.div [ Html.Attributes.style "display" "flex", Html.Attributes.style "gap" "0.5em", Html.Attributes.style "align-items" "center" ]
                                [ viewPointSelector
                                    { onSelect = UpdateSplitPoint splitListPos, hasPosition = state.position /= Nothing }
                                    selectable
                                    selectedRef
                                , Html.button
                                    [ Html.Events.onClick (RemoveSplitPoint splitListPos)
                                    , Html.Attributes.class "button-4"
                                    ]
                                    [ Html.text "Remove" ]
                                ]
                    in
                    List.indexedMap dropdownRow ep.splitPoints
                        ++ [ Html.button
                                [ Html.Events.onClick AddSplitPoint
                                , Html.Attributes.class "button-4"
                                , Html.Attributes.disabled (List.length ep.splitPoints >= availableCount)
                                ]
                                [ Html.text "Add" ]
                           ]
            ]
        )
    , Html.hr [] []
    , viewTotalDistanceOptions state
    , optionGroup "Marker interval"
        (List.concat
            [ [ checkbox (ep.distanceMarkerInterval == Nothing)
                    (UpdateDistanceMarkerInterval
                        (if ep.distanceMarkerInterval == Nothing then
                            Just 10000

                         else
                            Nothing
                        )
                    )
                    "Auto interval"
              ]
            , case ep.distanceMarkerInterval of
                Just interval ->
                    [ Html.input
                        [ Html.Attributes.type_ "range"
                        , Html.Attributes.min "1"
                        , Html.Attributes.max "50"
                        , Html.Attributes.step "1"
                        , Html.Attributes.value <| String.fromFloat (interval / 1000)
                        , Html.Events.onInput (String.toFloat >> Maybe.withDefault 10 >> (\km -> UpdateDistanceMarkerInterval (Just (km * 1000))))
                        ]
                        []
                    , Html.text (formatKm 0 interval)
                    ]

                Nothing ->
                    []
            , [ checkbox ep.distanceMarkerSegmentEnds (UpdateDistanceMarkerSegmentEnds (not ep.distanceMarkerSegmentEnds)) "Mark segment start/finish" ]
            ]
        )
    , Html.hr [] []
    ]


{-| The "Total distance" selector (mode dropdown plus the reference-distance / reference-point
input it implies). Shared by the cuesheet and the elevation profile so the single
`state.cuesheet.totalDistanceDisplay` setting can be changed from either panel.
-}
viewTotalDistanceOptions : State -> Html Msg
viewTotalDistanceOptions state =
    let
        cs =
            state.cuesheet

        maybeTracks =
            maybeFromloadableResource state.tracks

        maxDistance =
            maybeTracks
                |> Maybe.map (\ts -> lastTrackpointDistance ts.current.trackpoints)

        filteredWps =
            maybeTracks
                |> Maybe.map
                    (\ts ->
                        let
                            currentEffective =
                                effectiveWaypoints ts.current
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
                |> Maybe.map (.current >> (\track -> indexedFilteredWaypoints track filteredWps))
                |> Maybe.withDefault []

        defaultRef =
            List.head indexedFiltered |> Maybe.map (Tuple.first >> AtWaypoint) |> Maybe.withDefault AtRoutePosition

        -- The mode dropdown only picks the mode; which point it refers to is the selector
        -- below, so switching into a point mode starts from a default reference.
        parseModeDropdown maybeStr =
            case maybeStr of
                Just "to waypoint" ->
                    UpdateTotalDistanceDisplay (Just (ToWaypoint defaultRef))

                Just "from waypoint" ->
                    UpdateTotalDistanceDisplay (Just (FromWaypoint defaultRef))

                _ ->
                    maybeStr
                        |> Maybe.map parseTotalDistanceDisplay
                        |> Maybe.withDefault Nothing
                        |> UpdateTotalDistanceDisplay

        modeItem mode =
            Dropdown.Item (formatTotalDistanceDisplayMode mode) (formatTotalDistanceDisplayLabel mode) True

        pointSelector ref =
            [ viewPointSelector
                { onSelect = UpdateSelectedPoint, hasPosition = state.position /= Nothing }
                indexedFiltered
                ref
            ]
    in
    optionGroup "Total distance"
        ([ Dropdown.dropdown
            (Dropdown.Options
                [ modeItem FromZero
                , modeItem ToFinish
                , modeItem ToPoint
                , modeItem (ToWaypoint defaultRef)
                , modeItem (FromWaypoint defaultRef)
                , modeItem PercentProgress
                , modeItem PercentRemaining
                , modeItem None
                ]
                Nothing
                parseModeDropdown
            )
            []
            (Just <| formatTotalDistanceDisplayMode cs.totalDistanceDisplay)
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

                    ToWaypoint ref ->
                        pointSelector ref

                    FromWaypoint ref ->
                        pointSelector ref

                    _ ->
                        []
               )
        )


viewCuesheetOptionsPanel : State -> List (Html Msg)
viewCuesheetOptionsPanel state =
    let
        cs =
            state.cuesheet
    in
    [ optionGroup "Start/Finish"
        [ checkbox cs.showStartFinish (UpdateShowStartFinish (not cs.showStartFinish)) "Show start/finish"
        ]
    , Html.hr [] []
    , viewTotalDistanceOptions state
    , Html.hr [] []
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
        Loaded tracks ->
            let
                maxDist =
                    lastTrackpointDistance tracks.current.trackpoints

                locationStatus text =
                    Html.p
                        [ Html.Attributes.style "font-size" "0.8em"
                        , Html.Attributes.style "margin" "0.5em 0"
                        ]
                        [ Html.text text ]
            in
            List.concat
                [ [ Html.hr [] []
                  , optionGroup "Position"
                        (Html.input
                            [ Html.Attributes.type_ "range"
                            , Html.Attributes.min "0"
                            , Html.Attributes.max (String.fromFloat maxDist)
                            , Html.Attributes.step "100"
                            , Html.Attributes.value (String.fromFloat (Maybe.withDefault 0 state.position))
                            , Html.Events.onInput (String.toFloat >> UpdatePosition)
                            , Html.Attributes.disabled state.trackingEnabled
                            ]
                            []
                            :: (case state.position of
                                    Just _ ->
                                        [ viewButton [ Html.Attributes.style "width" "100%" ] "Clear position" (UpdatePosition Nothing) ]

                                    Nothing ->
                                        []
                               )
                        )
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
                , case ( state.locationError, state.location, state.trackingEnabled ) of
                    ( Just err, _, _ ) ->
                        [ locationStatus (Location.locationErrorToString err) ]

                    ( Nothing, Just loc, _ ) ->
                        [ locationStatus ("Accuracy: " ++ String.fromFloat (toFloat (round (loc.accuracy * 10)) / 10) ++ "m") ]

                    -- tracking but no fix yet; nothing to say when idle and cleared
                    ( Nothing, Nothing, True ) ->
                        [ locationStatus "No location fix" ]

                    ( Nothing, Nothing, False ) ->
                        []
                ]

        _ ->
            []



-- SHARED VIEW HELPERS


offRouteColour =
    "orangered"


viewErrorPanel : String -> Html Msg
viewErrorPanel error =
    Html.div [ Html.Attributes.class "error_panel" ] [ Html.text error ]


{-| Warns that live view is active without a position, so the whole route is shown rather
than a window around it. Empty when a position is set or in static view.
-}
liveNoPositionWarning : State -> Html Msg
liveNoPositionWarning state =
    if state.viewMode == LiveView && state.position == Nothing then
        Html.div [ Html.Attributes.class "warning_panel" ]
            [ Html.text "Live view has no position — showing the whole route. Set a position or start tracking." ]

    else
        Html.text ""


viewButton : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButton attrs text onClickMsg =
    Html.button
        ([ Html.Events.onClick onClickMsg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


{-| Waypoints can be unnamed — `AddWaypoint` creates them with an empty name — so fall back
to something that still identifies which one is meant.
-}
waypointDisplayName : GpxApi.Waypoint -> String
waypointDisplayName waypoint =
    if String.isEmpty (String.trim waypoint.name) then
        "Unnamed waypoint (" ++ formatKm 1 waypoint.distance ++ ")"

    else
        waypoint.name


{-| The one control for picking a point on the route. Offers the given waypoints plus the
rider's position, the latter disabled — rather than hidden — when no position is set, so the
option stays discoverable and the list does not change shape as a fix comes and goes.
-}
viewPointSelector : { onSelect : PointRef -> Msg, hasPosition : Bool } -> List ( Int, GpxApi.Waypoint ) -> PointRef -> Html Msg
viewPointSelector { onSelect, hasPosition } indexed selected =
    Dropdown.dropdown
        (Dropdown.Options
            (Dropdown.Item (formatPointRef AtRoutePosition) routePositionName hasPosition
                :: List.map
                    (\( idx, wp ) ->
                        Dropdown.Item (formatPointRef (AtWaypoint idx)) (waypointDisplayName wp ++ " (" ++ formatKm 1 wp.distance ++ ")") True
                    )
                    indexed
            )
            Nothing
            (\maybeStr ->
                case maybeStr |> Maybe.andThen parsePointRef of
                    Just ref ->
                        onSelect ref

                    Nothing ->
                        Ignore
            )
        )
        []
        (Just (formatPointRef selected))


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

        "% progress" ->
            Just PercentProgress

        "% remaining" ->
            Just PercentRemaining

        "hide" ->
            Just None

        _ ->
            -- The reference suffix was written by formatPointRef, so a stored
            -- "to waypoint:3" from before a position was selectable still parses.
            case String.split ":" v of
                [ mode, refStr ] ->
                    parsePointRef refStr
                        |> Maybe.andThen
                            (\ref ->
                                if mode == "to waypoint" then
                                    Just (ToWaypoint ref)

                                else if mode == "from waypoint" then
                                    Just (FromWaypoint ref)

                                else
                                    Nothing
                            )

                _ ->
                    if String.startsWith "to waypoint" v then
                        Just (ToWaypoint (AtWaypoint 0))

                    else if String.startsWith "from waypoint" v then
                        Just (FromWaypoint (AtWaypoint 0))

                    else
                        Nothing


{-| The stored form of a display mode, including which point it refers to.
-}
formatTotalDistanceDisplay : TotalDistanceDisplay -> String
formatTotalDistanceDisplay v =
    case v of
        ToWaypoint ref ->
            formatTotalDistanceDisplayMode v ++ ":" ++ formatPointRef ref

        FromWaypoint ref ->
            formatTotalDistanceDisplayMode v ++ ":" ++ formatPointRef ref

        other ->
            formatTotalDistanceDisplayMode other


{-| The mode alone, without the point it refers to. This is what the mode dropdown's options
are keyed by, since choosing a mode there does not choose a point.
-}
formatTotalDistanceDisplayMode : TotalDistanceDisplay -> String
formatTotalDistanceDisplayMode v =
    case v of
        FromZero ->
            "from zero"

        ToFinish ->
            "to finish"

        ToPoint ->
            "to point"

        ToWaypoint _ ->
            "to waypoint"

        FromWaypoint _ ->
            "from waypoint"

        PercentProgress ->
            "% progress"

        PercentRemaining ->
            "% remaining"

        None ->
            "hide"


{-| What the user reads in the mode dropdown. Deliberately diverges from the stored form:
`ToWaypoint`/`FromWaypoint` can now refer to a route position as well as a waypoint, and
"to point" reads better for that than "to waypoint" — which leaves "to distance" as the
clearer name for the freeform-metres mode that used to be called "to point".
-}
formatTotalDistanceDisplayLabel : TotalDistanceDisplay -> String
formatTotalDistanceDisplayLabel v =
    case v of
        ToPoint ->
            "to distance"

        ToWaypoint _ ->
            "to point"

        FromWaypoint _ ->
            "from point"

        other ->
            formatTotalDistanceDisplayMode other



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

        "relative" ->
            Just RelativeTab

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

        RelativeTab ->
            "relative"



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
            , if ew.created then
                Just ( "created", Json.Encode.bool True )

              else
                Nothing
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
    Json.Decode.map4 EditableWaypoint
        (Json.Decode.field "original" GpxApi.decodeWaypoint)
        (Json.Decode.field "deleted" Json.Decode.bool)
        (Json.Decode.oneOf [ Json.Decode.field "created" Json.Decode.bool, Json.Decode.succeed False ])
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

        rel =
            state.relative
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
            , state.position |> Maybe.map (\pos -> ( "position", Json.Encode.float pos ))
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
            , Just ( "splitPoints", Json.Encode.list (formatPointRef >> Json.Encode.string) ep.splitPoints )
            , Just ( "liveLookahead", Json.Encode.float ep.liveLookahead )
            , Just ( "liveLookbehind", Json.Encode.float ep.liveLookbehind )
            , Just ( "labelHeightGain", Json.Encode.float ep.labelHeightGain )
            , ep.distanceMarkerInterval |> Maybe.map (\m -> ( "distanceMarkerInterval", Json.Encode.float m ))
            , Just ( "distanceMarkerSegmentEnds", Json.Encode.bool ep.distanceMarkerSegmentEnds )
            , Just ( "totalDistanceDisplay", Json.Encode.string (formatTotalDistanceDisplay cs.totalDistanceDisplay) )
            , Just ( "referencePoint", Json.Encode.float cs.referencePoint )
            , Just ( "itemSpacing", Json.Encode.int cs.itemSpacing )
            , Just ( "distanceDetail", Json.Encode.int cs.distanceDetail )
            , Just ( "showStartFinish", Json.Encode.bool cs.showStartFinish )
            , Just ( "offRouteThreshold", Json.Encode.float state.offRouteThreshold )
            , Just ( "showOffRouteWaypoints", Json.Encode.bool state.showOffRouteWaypoints )
            , Just ( "showOffRouteDistance", Json.Encode.bool state.showOffRouteDistance )
            , Just ( "relativeStart", Json.Encode.string (formatPointRef rel.start) )
            , Just ( "relativeEnd", Json.Encode.string (formatPointRef rel.end) )
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

        defRel =
            defaultRelativeOptions
    in
    Json.Decode.succeed
        (\tracks activeTab showOptions trackingIntervalSec categoryFilterEnabled filteredCategories fontSize trackHeight trackThickness showIntensity intensityTau position viewMode splitMode splitEquidistantCount splitPoints legacySplitWaypointIndices liveLookahead liveLookbehind labelHeightGain distanceMarkerInterval distanceMarkerSegmentEnds totalDistanceDisplay referencePoint itemSpacing distanceDetail showStartFinish showOffRouteDistance offRouteThreshold showOffRouteWaypoints relativeStart relativeEnd ->
            { tracks = loadableResourceFromMaybe tracks
            , showOptions = showOptions |> Maybe.withDefault defaultState.showOptions
            , activeTab = activeTab |> Maybe.andThen parseTab |> Maybe.withDefault defaultState.activeTab
            , position = position
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
                , activeSplitMode =
                    case splitMode of
                        Just "waypoints" ->
                            WaypointsMode

                        _ ->
                            EquidistantMode
                , splitEquidistantCount = splitEquidistantCount |> Maybe.withDefault 1
                , splitPoints =
                    case splitPoints of
                        Just refs ->
                            List.filterMap parsePointRef refs

                        -- State saved before split boundaries could be a route position
                        Nothing ->
                            legacySplitWaypointIndices |> Maybe.withDefault [] |> List.map AtWaypoint
                , liveLookahead = liveLookahead |> Maybe.withDefault defEp.liveLookahead
                , liveLookbehind = liveLookbehind |> Maybe.withDefault defEp.liveLookbehind
                , labelHeightGain = labelHeightGain |> Maybe.withDefault defEp.labelHeightGain
                , distanceMarkerInterval = distanceMarkerInterval
                , distanceMarkerSegmentEnds = distanceMarkerSegmentEnds |> Maybe.withDefault defEp.distanceMarkerSegmentEnds
                }
            , cuesheet =
                { totalDistanceDisplay = totalDistanceDisplay |> Maybe.andThen parseTotalDistanceDisplay |> Maybe.withDefault defCs.totalDistanceDisplay
                , referencePoint = referencePoint |> Maybe.withDefault defCs.referencePoint
                , itemSpacing = itemSpacing |> Maybe.withDefault defCs.itemSpacing
                , distanceDetail = distanceDetail |> Maybe.withDefault defCs.distanceDetail
                , showStartFinish = showStartFinish |> Maybe.withDefault defCs.showStartFinish
                }
            , relative =
                { start = relativeStart |> Maybe.andThen parsePointRef |> Maybe.withDefault defRel.start
                , end = relativeEnd |> Maybe.andThen parsePointRef |> Maybe.withDefault defRel.end
                }
            , stateDecodeError = Nothing
            , splitSegments = Nothing
            , profilePixelWidth = Nothing
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
        |> andMap (maybeField "position" Json.Decode.float)
        |> andMap (maybeField "viewMode" Json.Decode.string)
        |> andMap (maybeField "splitMode" Json.Decode.string)
        |> andMap (maybeField "splitEquidistantCount" Json.Decode.int)
        |> andMap (maybeField "splitPoints" (Json.Decode.list Json.Decode.string))
        |> andMap (maybeField "splitWaypointIndices" (Json.Decode.list Json.Decode.int))
        |> andMap (maybeField "liveLookahead" Json.Decode.float)
        |> andMap (maybeField "liveLookbehind" Json.Decode.float)
        |> andMap (maybeField "labelHeightGain" Json.Decode.float)
        |> andMap (maybeField "distanceMarkerInterval" Json.Decode.float)
        |> andMap (maybeField "distanceMarkerSegmentEnds" Json.Decode.bool)
        |> andMap (maybeField "totalDistanceDisplay" Json.Decode.string)
        |> andMap (maybeField "referencePoint" Json.Decode.float)
        |> andMap (maybeField "itemSpacing" Json.Decode.int)
        |> andMap (maybeField "distanceDetail" Json.Decode.int)
        |> andMap (maybeField "showStartFinish" Json.Decode.bool)
        |> andMap (maybeField "showOffRouteDistance" Json.Decode.bool)
        |> andMap (maybeField "offRouteThreshold" Json.Decode.float)
        |> andMap (maybeField "showOffRouteWaypoints" Json.Decode.bool)
        |> andMap (maybeField "relativeStart" Json.Decode.string)
        |> andMap (maybeField "relativeEnd" Json.Decode.string)


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


port profileWidthChanged : (Int -> msg) -> Sub msg


port requestSplitsGpx : String -> Cmd msg



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
