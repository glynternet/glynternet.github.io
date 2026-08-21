port module Main exposing (main)

import Browser
import Browser.Navigation
import Dict
import Dropdown
import File exposing (File)
import File.Select
import Format
import GpxApi
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Events
import Http
import Json.Decode
import Json.Encode
import List.Extra
import Location
import String
import Svg
import Svg.Attributes
import Task
import Time
import Ui
import Url
import Wallclock
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
        , storeStateFailed StoreStateFailed

        -- Only the Pace tab shows a clock, and only to the minute, so nothing else pays for
        -- keeping one running.
        , if state.activeTab == PaceTab then
            Time.every 10000 GotNow

          else
            Sub.none
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
    , pace : PaceOptions

    -- Off-route
    , offRouteThreshold : Float
    , showOffRouteWaypoints : Bool
    , showOffRouteDistance : Bool

    -- Transient (never persisted)
    , stateDecodeError : Maybe String
    , storageError : Maybe String
    , splitSegments : Maybe GpxApi.SplitResult
    , profilePixelWidth : Maybe Int

    -- The device clock, for the Pace tab's arrival times. Transient because a stored clock
    -- reading is a wrong one the moment it is read back; `zone` stays UTC only for the
    -- moment before `Time.here` lands.
    , now : Maybe Time.Posix
    , zone : Time.Zone
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
    | PaceTab


type ViewMode
    = LiveView
    | StaticView


type ActiveSplitMode
    = EquidistantMode
    | PointsMode
    | CategoriesMode


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


{-| A point on the route the user has picked out: one of the track's waypoints, wherever they
are, or either end of the route.

Every flow that asks the user to choose a point on the route stores one of these, so the
same selector serves all of them. `AtRoutePosition` resolves against `state.position`,
which may be unset — hence the `Maybe` on the resolvers below. It is the point on the route
nearest the rider, not the rider: a GPS fix off the route resolves to what it matched, and
the gap is the resolved waypoint's off-route distance.

`AtWaypoint` indexes `editableWaypoints`, deliberately including the deleted ones: that index
is stable, whereas a position in the resolved-and-filtered list shifts under the user as soon
as an earlier waypoint is marked deleted or filtered out. It is also the index space the
edit flows already maintain — see `removeWaypointAt`, `WaypointDeleted` and `ResetWaypoints`.

`AtRouteStart` / `AtRouteEnd` are the ends of the track itself, so they stand whether or not
the GPX puts a waypoint there and whatever the waypoint filters hide. Only the flows that
compare two arbitrary points offer them — see `viewPointSelector`'s `offerRouteEnds` for why
the split and cuesheet selectors do not.

-}
type PointRef
    = AtWaypoint Int
    | AtRoutePosition
    | AtRouteStart
    | AtRouteEnd


{-| Resolves a reference to the waypoint it stands for, or Nothing when it no longer stands
for one — a deleted waypoint, or `AtRoutePosition` with no position set. A position becomes a
synthetic waypoint, carrying the cumulative climb to there and, when a GPS fix is what set
the position, how far off route that fix is. The route's own ends become synthetic waypoints
too, with no categories of their own — nothing in the file gave them any.

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

        AtRouteStart ->
            Just (GpxApi.Waypoint 0 routeStartName [] 0 0 0)

        AtRouteEnd ->
            Just
                (GpxApi.Waypoint (lastTrackpointDistance track.trackpoints)
                    routeEndName
                    []
                    (Tuple.first track.gainLoss)
                    (Tuple.second track.gainLoss)
                    0
                )


{-| The route distance a reference stands for, for the flows that only need to place the
point along the route. Defined through `resolvePointRef` so there is a single answer to what
an `AtWaypoint` index means; a GPS fix cannot move a point along the route, so none is needed.
-}
refDistance : Maybe Float -> EditableTrack -> PointRef -> Maybe Float
refDistance position track =
    resolvePointRef position Nothing track >> Maybe.map .distance


{-| Remaps a reference after the waypoint at `removedIndex` has been dropped from
`editableWaypoints`, which shifts every later index down by one. Only `AtWaypoint` is
addressed by index, so every other reference survives untouched.
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

        AtRouteStart ->
            ref

        AtRouteEnd ->
            ref


routePositionName : String
routePositionName =
    "Position on route"


routeStartName : String
routeStartName =
    "Start of route"


routeEndName : String
routeEndName =
    "End of route"


{-| The stored form of a reference: a waypoint as its bare index, everything else as a word no
index can collide with. Doubles as the option value in `viewPointSelector`, and as the suffix
after the colon in a `TotalDistanceDisplay` — so it must stay colon-free.
-}
formatPointRef : PointRef -> String
formatPointRef ref =
    case ref of
        AtWaypoint idx ->
            String.fromInt idx

        AtRoutePosition ->
            "position"

        AtRouteStart ->
            "start"

        AtRouteEnd ->
            "end"


parsePointRef : String -> Maybe PointRef
parsePointRef s =
    case s of
        "position" ->
            Just AtRoutePosition

        "start" ->
            Just AtRouteStart

        "end" ->
            Just AtRouteEnd

        _ ->
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
    , splitCategories : List String
    , liveLookahead : Float
    , liveLookbehind : Float
    , labelHeightGain : Float
    , distanceMarkerInterval : Maybe Float
    , distanceMarkerSegmentEnds : Bool
    }


type alias CuesheetOptions =
    { totalDistanceDisplay : TotalDistanceDisplay
    , referenceDistance : Float
    , itemSpacing : Int
    , distanceDetail : Int
    , showStartFinish : Bool
    }


{-| The two points the Relative tab compares, and whether each one's card is folded down to
its heading. The folds sit beside the points because they are the same tab's view state, and
are saved with the rest of it so a tab tidied for the road stays that way.
-}
type alias RelativeOptions =
    { start : PointRef
    , end : PointRef
    , startCollapsed : Bool
    , endCollapsed : Bool
    }


{-| The two points the Pace tab estimates between, and where the speed it estimates at comes
from.

Both a set speed and an elapsed time are kept whichever source is active, so switching to the
other and back does not throw away what was typed — the same reason `ElevationProfileOptions`
keeps every split mode's settings side by side rather than hanging them off `activeSplitMode`.

-}
type alias PaceOptions =
    { start : PointRef
    , end : PointRef
    , activePaceSource : PaceSource
    , speedKmh : Float
    , elapsedAtStartSec : Float
    , rideStart : String
    }


{-| Where the Pace tab's speed comes from: a figure the rider set, or the ride so far — how
much route is behind them over how long it has taken — with the elapsed time either typed in
or counted off the clock from the moment they set off.

`FromRideStart` is the one that keeps itself right: a typed elapsed time is a snapshot that
goes stale the moment the rider stops retyping it, whereas a time they set off at stays true
all day and the pace follows the clock from there.

`rideStart` is held as the raw value of a `datetime-local` input rather than as an instant,
because that is what the control gives and what it wants back; `Wallclock.parseLocalDateTime` reads it,
and anything unparseable — including the empty default — simply yields no pace.

-}
type PaceSource
    = SetSpeed
    | FromElapsed
    | FromRideStart


type TotalDistanceDisplay
    = FromZero
    | ToFinish
    | ToDistance
    | ToPoint PointRef
    | FromPoint PointRef
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
    , splitCategories = []
    , liveLookahead = 5000
    , liveLookbehind = 2000
    , labelHeightGain = 1.0
    , distanceMarkerInterval = Nothing
    , distanceMarkerSegmentEnds = False
    }


defaultCuesheetOptions : CuesheetOptions
defaultCuesheetOptions =
    { totalDistanceDisplay = FromZero
    , referenceDistance = 1000
    , itemSpacing = defaultSpacing
    , distanceDetail = defaultDistanceDetail
    , showStartFinish = False
    }


defaultRelativeOptions : RelativeOptions
defaultRelativeOptions =
    { start = AtRoutePosition
    , end = AtWaypoint 0
    , startCollapsed = False
    , endCollapsed = False
    }


{-| Where the rider is now to where the route ends: the arrival the tab exists to answer for,
before anything has been chosen.
-}
defaultPaceOptions : PaceOptions
defaultPaceOptions =
    { start = AtRoutePosition
    , end = AtRouteEnd
    , activePaceSource = SetSpeed
    , speedKmh = 20
    , elapsedAtStartSec = 0
    , rideStart = ""
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
    , pace = defaultPaceOptions
    , offRouteThreshold = 100
    , showOffRouteWaypoints = True
    , showOffRouteDistance = False
    , stateDecodeError = Nothing
    , storageError = Nothing
    , splitSegments = Nothing
    , profilePixelWidth = Nothing
    , now = Nothing
    , zone = Time.utc
    }


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState url key =
    let
        nav =
            Navigation key url.path

        base =
            Model nav defaultState

        -- Asked for once here rather than per branch, so however the state is arrived at the
        -- Pace tab has a clock and a zone to render its arrival times against.
        withClock ( model, cmd ) =
            ( model, Cmd.batch [ cmd, Task.perform GotZone Time.here, Task.perform GotNow Time.now ] )
    in
    withClock <|
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
    | StoreStateFailed String
    | DismissStorageError
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
    | SetSplitCategoryEnabled String Bool
    | UpdateLiveLookahead Float
    | UpdateLiveLookbehind Float
    | UpdateDistanceMarkerInterval (Maybe Float)
    | UpdateDistanceMarkerSegmentEnds Bool
    | UpdatePosition (Maybe Float)
      -- Cuesheet
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdateReferenceDistance Float
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
    | SetRelativeStartCollapsed Bool
    | SetRelativeEndCollapsed Bool
    | SetPaceStart PointRef
    | SetPaceEnd PointRef
    | SetPaceSource PaceSource
    | UpdatePaceSpeed Float
    | UpdatePaceElapsed Float
    | UpdatePaceRideStart String
    | GotNow Time.Posix
    | GotZone Time.Zone
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

        updatePace change =
            updateAndStoreModel (updateState { s | pace = change s.pace })

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

        StoreStateFailed error ->
            ( updateState { s | storageError = Just error }, Cmd.none )

        DismissStorageError ->
            ( updateState { s | storageError = Nothing }, Cmd.none )

        ShowOptions show ->
            updateAndStoreModel (updateState { s | showOptions = show })

        SwitchTab tab ->
            updateAndStoreModel (updateState { s | activeTab = tab })
                -- Without this the Pace tab's clock would be up to a whole tick out of date
                -- the moment it is opened.
                |> Tuple.mapSecond
                    (\cmd ->
                        if tab == PaceTab then
                            Cmd.batch [ cmd, Task.perform GotNow Time.now ]

                        else
                            cmd
                    )

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
                            let
                                newCategories =
                                    initialFilteredCategories (List.concatMap .waypoints gpxTracks)
                            in
                            updateSplitAndStore
                                (updateState
                                    { s
                                        | tracks =
                                            case Zipper.fromList <| List.map editableTrackFromGpxTrack gpxTracks of
                                                Nothing ->
                                                    Error "No tracks available in uploaded GPX"

                                                Just positionalTracks ->
                                                    Loaded positionalTracks
                                        , filteredCategories = newCategories
                                        , elevationProfile =
                                            let
                                                ep =
                                                    s.elevationProfile
                                            in
                                            { ep
                                                | splitPoints = []

                                                -- Categories are named, not indexed, so a
                                                -- selection carries over to a route that has
                                                -- the same ones. Any the new route lacks are
                                                -- dropped rather than lingering invisibly:
                                                -- they would not appear as a checkbox to untick.
                                                , splitCategories = List.filter (\cat -> Dict.member cat newCategories) ep.splitCategories
                                            }
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
                        -- now stale. A split that names no waypoint is never stale.
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

                                                            _ ->
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

        SetSplitCategoryEnabled category enabled ->
            let
                ep =
                    s.elevationProfile
            in
            updateSplitAndStore
                (updateState
                    { s
                        | elevationProfile =
                            { ep
                                | splitCategories =
                                    if enabled then
                                        ep.splitCategories ++ [ category ]

                                    else
                                        List.filter ((/=) category) ep.splitCategories
                            }
                    }
                )

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

        UpdateReferenceDistance distance ->
            let
                cs =
                    s.cuesheet
            in
            updateAndStoreModel (updateState { s | cuesheet = { cs | referenceDistance = distance } })

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
                        ToPoint _ ->
                            ToPoint ref

                        FromPoint _ ->
                            FromPoint ref

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

        SetRelativeStartCollapsed collapsed ->
            let
                rel =
                    s.relative
            in
            updateAndStoreModel (updateState { s | relative = { rel | startCollapsed = collapsed } })

        SetRelativeEndCollapsed collapsed ->
            let
                rel =
                    s.relative
            in
            updateAndStoreModel (updateState { s | relative = { rel | endCollapsed = collapsed } })

        SetPaceStart ref ->
            updatePace (\pace -> { pace | start = ref })

        SetPaceEnd ref ->
            updatePace (\pace -> { pace | end = ref })

        SetPaceSource source ->
            updatePace (\pace -> { pace | activePaceSource = source })

        UpdatePaceSpeed kmh ->
            updatePace (\pace -> { pace | speedKmh = kmh })

        UpdatePaceElapsed seconds ->
            updatePace (\pace -> { pace | elapsedAtStartSec = seconds })

        UpdatePaceRideStart rideStart ->
            updatePace (\pace -> { pace | rideStart = rideStart })

        -- The clock is never stored: reading a stale one back would date every arrival time
        -- the tab shows.
        GotNow now ->
            ( updateState { s | now = Just now }, Cmd.none )

        GotZone zone ->
            ( updateState { s | zone = zone }, Cmd.none )

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
                    -- The decoded state carries none of the live readings, so they are lifted
                    -- across rather than being reset by a state import.
                    { model
                        | state =
                            withLiveSplit
                                { decoded
                                    | profilePixelWidth = model.state.profilePixelWidth
                                    , now = model.state.now
                                    , zone = model.state.zone
                                }
                    }
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

                -- "waypoints" is the WASM module's vocabulary, not ours:
                -- elevation.SplitRequest is defined in github.com/glynternet/gpx, and the
                -- mode splits at the distances given whatever they came from.
                splitAtChosenDistances =
                    [ ( "mode", Json.Encode.string "waypoints" )
                    , ( "distances", Json.Encode.list Json.Encode.float (splitDistances state tracks.current) )
                    ]
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

                                    PointsMode ->
                                        splitAtChosenDistances

                                    CategoriesMode ->
                                        splitAtChosenDistances
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
                        ToPoint ref ->
                            ToPoint (shiftPointRef i ref)

                        FromPoint ref ->
                            FromPoint (shiftPointRef i ref)

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


{-| Resolves a chosen point, but only ever to a waypoint the dropdown is still offering.
Going through `selectable` rather than the whole track means a reference to one the filters
have hidden reads as "nothing chosen" instead of silently standing for something the rider
cannot see. Nothing else the dropdown offers is a waypoint of the track's, so nothing else
can be filtered away.
-}
selectedWaypointFor : State -> EditableTrack -> List ( Int, GpxApi.Waypoint ) -> PointRef -> Maybe GpxApi.Waypoint
selectedWaypointFor state track selectable ref =
    case ref of
        AtWaypoint idx ->
            selectable |> List.Extra.find (\( i, _ ) -> i == idx) |> Maybe.map Tuple.second

        _ ->
            resolvePointRef state.position state.location track ref


{-| What to say in place of figures a chosen point could not be resolved for. An unset
position is the one case with a way out of it, so it says what that is; anything else is a
waypoint that has gone, and only the caller knows what it was being chosen for.
-}
unresolvedPointNotice : PointRef -> String -> String
unresolvedPointNotice ref fallback =
    case ref of
        AtRoutePosition ->
            "This needs a position on the route. Set one with the Position slider in the options panel, or start tracking."

        _ ->
            fallback


{-| The points the elevation profile offers as split boundaries. Waypoints come first so
that "Add" keeps working through them in route order before reaching for the position.
-}
selectableSplitPoints : State -> EditableTrack -> List PointRef
selectableSplitPoints state track =
    List.map (Tuple.first >> AtWaypoint) (selectableWaypoints state track)
        ++ positionRefIfSet state


{-| Whether a waypoint carries any of the given categories. An uncategorised waypoint counts
as the unknown category, exactly as `categoryPredicate` treats it, so "unknown" can be split
on like any other.
-}
inAnyCategory : List String -> GpxApi.Waypoint -> Bool
inAnyCategory categories w =
    case w.categories of
        [] ->
            List.member unknownCategory categories

        cats ->
            List.any (\cat -> List.member cat categories) cats


{-| The distances the current mode splits the route at, sorted, de-duplicated and stripped of
the route's own ends. `elevation.SplitByWaypoints` brackets whatever it is given with 0 and the
total distance, so a repeated boundary — or one sitting on the start or finish, which a
"Start/Finish" category produces at both — would otherwise yield an empty segment.

A category split cuts at every waypoint carrying **any** of the chosen categories, which is
what makes choosing more than one useful: "Water" and "Campground" splits at all of both, not
at the few tagged with both. Its candidates come from `selectableWaypoints` so that a waypoint
hidden by the category filter or the off-route threshold cannot silently split the route.

-}
splitDistances : State -> EditableTrack -> List Float
splitDistances state track =
    (case state.elevationProfile.activeSplitMode of
        EquidistantMode ->
            []

        PointsMode ->
            List.filterMap (refDistance state.position track) state.elevationProfile.splitPoints

        CategoriesMode ->
            selectableWaypoints state track
                |> List.map Tuple.second
                |> List.filter (inAnyCategory state.elevationProfile.splitCategories)
                |> List.map .distance
    )
        |> List.sort
        |> List.Extra.unique
        |> List.filter (\distance -> distance > 0 && distance < lastTrackpointDistance track.trackpoints)


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


{-| Repoints a display mode whose reference waypoint has been filtered away or deleted. Only
a waypoint can be filtered away, so every other reference is left alone.
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

                AtRouteStart ->
                    True

                AtRouteEnd ->
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
        ToPoint ref ->
            correct ToPoint List.Extra.last ref

        FromPoint ref ->
            correct FromPoint List.head ref

        _ ->
            display


{-| The point the current display mode measures to or from, resolved for the modes that have
one. Shared by the cuesheet and the elevation profile's distance markers.
-}
referenceWaypoint : State -> EditableTrack -> Maybe GpxApi.Waypoint
referenceWaypoint state track =
    case state.cuesheet.totalDistanceDisplay of
        ToPoint ref ->
            resolvePointRef state.position state.location track ref

        FromPoint ref ->
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
                        -- The position and the route's ends are always available, whatever
                        -- the waypoint filters do
                        AtRoutePosition ->
                            ref

                        AtRouteStart ->
                            ref

                        AtRouteEnd ->
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
            (viewWarningBanner "Failed to restore saved state: " DismissStateDecodeError state.stateDecodeError
                ++ viewWarningBanner "Couldn't save this route, so it won't be here when you come back: " DismissStorageError state.storageError
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

                                    PaceTab ->
                                        viewPaceTab state tracks
                                ]
                            ]
                   )
            )
        ]


viewWarningBanner : String -> Msg -> Maybe String -> List (Html Msg)
viewWarningBanner title dismiss maybeError =
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
                    [ Html.strong [] [ Html.text title ]
                    , Html.text (String.left 500 error)
                    ]
                , Html.button
                    [ Html.Events.onClick dismiss
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
            , Html.Attributes.style "border-radius" "0"
            , if activeTab == RelativeTab then
                Html.Attributes.style "font-weight" "bold"

              else
                Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text "Relative" ]
        , Html.button
            [ Html.Events.onClick (SwitchTab PaceTab)
            , Html.Attributes.class "button-4"
            , Html.Attributes.style "border-radius" "0 4px 4px 0"
            , if activeTab == PaceTab then
                Html.Attributes.style "font-weight" "bold"

              else
                Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text "Pace" ]
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
                                            , referenceDistance = cs.referenceDistance
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
displayedDistanceValue mode finishDist referenceDistance refWaypoint distance =
    case mode of
        None ->
            Nothing

        FromZero ->
            Just distance

        ToFinish ->
            Just (finishDist - distance)

        ToDistance ->
            Just (referenceDistance - distance)

        ToPoint _ ->
            refWaypoint |> Maybe.map (\rw -> rw.distance - distance)

        FromPoint _ ->
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
    , referenceDistance : Float
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
            displayedDistanceValue cfg.mode cfg.finishDist cfg.referenceDistance cfg.refWaypoint dist
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
                            Format.percent value

                        else
                            Format.km cfg.detail value
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
            [ Html.text <| Format.km 1 maxDistance ++ " " ++ Format.eleGainLoss gain loss ]
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
                    cumulativeGainLossAtDistance cs.referenceDistance tracks.current.trackpoints
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
                                        displayedDistanceValue cs.totalDistanceDisplay finishDist cs.referenceDistance refWaypoint waypoint.distance

                                    -- This waypoint is the point the total distance is measured to/from,
                                    -- so its to/from distance and elevation are both 0 and not worth showing.
                                    isReferencePoint =
                                        displayedDistance == Just 0

                                    waypointDistance =
                                        if isReferencePoint then
                                            Nothing

                                        else if displayIsPercent cs.totalDistanceDisplay then
                                            Maybe.map Format.percent displayedDistance

                                        else
                                            Maybe.map (Format.km cs.distanceDetail) displayedDistance

                                    waypointEle =
                                        if isReferencePoint then
                                            Nothing

                                        else
                                            case cs.totalDistanceDisplay of
                                                None ->
                                                    Nothing

                                                FromZero ->
                                                    Just (Format.eleGainLoss waypoint.gain waypoint.loss)

                                                ToFinish ->
                                                    lastWaypoint
                                                        |> Maybe.map
                                                            (\last ->
                                                                Format.eleGainLoss
                                                                    (last.gain - waypoint.gain)
                                                                    (last.loss - waypoint.loss)
                                                            )

                                                ToDistance ->
                                                    Just
                                                        (Format.eleGainLoss
                                                            (Tuple.first refPointEle - waypoint.gain)
                                                            (Tuple.second refPointEle - waypoint.loss)
                                                        )

                                                ToPoint _ ->
                                                    refWaypoint
                                                        |> Maybe.map
                                                            (\rw ->
                                                                Format.eleGainLoss
                                                                    (rw.gain - waypoint.gain)
                                                                    (rw.loss - waypoint.loss)
                                                            )

                                                FromPoint _ ->
                                                    refWaypoint
                                                        |> Maybe.map
                                                            (\rw ->
                                                                Format.eleGainLoss
                                                                    (waypoint.gain - rw.gain)
                                                                    (waypoint.loss - rw.loss)
                                                            )

                                                PercentProgress ->
                                                    Maybe.map2 Format.eleGainLossPercent
                                                        (safePercent waypoint.gain totalGain)
                                                        (safePercent waypoint.loss totalLoss)

                                                PercentRemaining ->
                                                    Maybe.map2 Format.eleGainLossPercent
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
                                                (safePercent dist finishDist |> Maybe.map Format.percent |> Maybe.withDefault "")
                                                    ++ " "
                                                    ++ Format.eleGainLossPercent
                                                        (safePercent gain totalGain |> Maybe.withDefault 0)
                                                        (safePercent loss totalLoss |> Maybe.withDefault 0)

                                            else
                                                Format.km cs.distanceDetail dist
                                                    ++ " "
                                                    ++ Format.eleGainLoss gain loss
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

        waypointFor =
            selectedWaypointFor state tracks.current selectable

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

                            _ ->
                                Nothing
                        )
                    )

        contextCardOrNotice card ref =
            case pointFor ref of
                Just point ->
                    viewRelativeContextCard tracks.current card point

                Nothing ->
                    Ui.noticePanel (unresolvedPointNotice ref card.fallback)

        -- No check for an empty waypoint list: the route's own ends are always there to
        -- compare, so the tab has something to say about a track carrying no waypoints at
        -- all — or none the category filter lets through.
        body =
            List.concat
                [ [ contextCardOrNotice
                        { role = "Start"
                        , fallback = "Choose a start point."
                        , collapsed = rel.startCollapsed
                        , onToggle = SetRelativeStartCollapsed (not rel.startCollapsed)
                        }
                        rel.start
                  ]

                -- Only travel between two points that both resolve; the notices in
                -- their place say which one still needs choosing.
                , case Maybe.map2 Tuple.pair (pointFor rel.start) (pointFor rel.end) of
                    Just ( startPoint, endPoint ) ->
                        [ viewRelativeTravelCard tracks.current selectable startPoint endPoint ]

                    Nothing ->
                        []
                , [ contextCardOrNotice
                        { role = "End"
                        , fallback = "Choose an end point."
                        , collapsed = rel.endCollapsed
                        , onToggle = SetRelativeEndCollapsed (not rel.endCollapsed)
                        }
                        rel.end
                  ]
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
        [ Ui.labelledControl "Start" (viewPointSelector { onSelect = SetRelativeStart, hasPosition = hasPosition, offerRouteEnds = True } selectable rel.start)
        , Ui.labelledControl "End" (viewPointSelector { onSelect = SetRelativeEnd, hasPosition = hasPosition, offerRouteEnds = True } selectable rel.end)
        ]


{-| Where one end of the comparison sits on the route, under a heading naming the role it
plays ("Start" / "End") so the two cards either side of the travel figures are told apart at
a glance. Built from the resolved point, so a route position — which `resolvePointRef` hands
back as a synthetic waypoint — reads exactly like a chosen waypoint, and the elevation shown
is the same one the travel figures were computed from.

Collapsed, the card keeps only its heading, and the point's name moves up into it so a card
folded out of the way still says which point it holds. The whole heading is the toggle.

-}
viewRelativeContextCard : EditableTrack -> { card | role : String, collapsed : Bool, onToggle : Msg } -> RelativePoint -> Html Msg
viewRelativeContextCard track card point =
    let
        waypoint =
            point.waypoint

        ( totalGain, totalLoss ) =
            track.gainLoss
    in
    Ui.card
        (Ui.cardHeading
            [ Html.Events.onClick card.onToggle
            , Html.Attributes.style "cursor" "pointer"
            , Html.Attributes.style "user-select" "none"
            , Html.Attributes.style "-webkit-user-select" "none"
            ]
            (Html.span
                [ Html.Attributes.style "font-size" "0.8em"
                , Html.Attributes.style "opacity" "0.6"
                ]
                [ Html.text
                    (if card.collapsed then
                        "▸"

                     else
                        "▾"
                    )
                ]
                :: Html.text card.role
                :: (if card.collapsed then
                        [ Html.span
                            [ Html.Attributes.style "font-weight" "normal"
                            , Html.Attributes.style "opacity" "0.75"
                            ]
                            [ Html.text (waypointDisplayName waypoint) ]
                        ]

                    else
                        []
                   )
            )
        )
        (if card.collapsed then
            []

         else
            List.filterMap identity
                [ Just (Html.div [ Html.Attributes.style "font-weight" "bold" ] [ Html.text (waypointDisplayName waypoint) ])
                , snapNote point |> Maybe.map Ui.note
                , case waypoint.categories of
                    [] ->
                        Nothing

                    categories ->
                        Just (Ui.row "Categories" (String.join ", " categories))
                , Just (Ui.row (elevationLabel point.elevationFromGps) (Format.m point.elevation))
                , Just (Ui.row "From start" (Format.km 1 waypoint.distance ++ " · " ++ Format.eleGainLoss waypoint.gain waypoint.loss))
                , Just
                    (Ui.row "To finish"
                        (Format.km 1 (lastTrackpointDistance track.trackpoints - waypoint.distance)
                            ++ " · "
                            ++ Format.eleGainLoss (totalGain - waypoint.gain) (totalLoss - waypoint.loss)
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
                ++ Format.m point.waypoint.offRoute
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
    Ui.card (Ui.cardHeading [] [ Html.text "Travel" ])
        [ Ui.section "Direct"
            (if usingFix then
                "from your GPS fix"

             else
                "between points on the route"
            )
            (List.filterMap identity
                [ Just (Ui.row "Distance" (Format.km 2 crowFlies))
                , Just (Ui.row "Bearing" (Format.bearing (Location.bearing start.latLon end.latLon)))
                , Just (Ui.row (elevationLabel (start.elevationFromGps || end.elevationFromGps)) (Format.signedM elevationDifference))
                , if crowFlies > 0 then
                    Just (Ui.row "Gradient" (Format.gradient (elevationDifference / crowFlies * 100)))

                  else
                    Nothing
                ]
            )
        , Ui.section "Along route"
            -- Only the route can say how far along it something is, so a GPS fix has to be
            -- taken as the route point it matched — worth saying when the two differ.
            (if usingFix then
                "your position taken as the nearest route point"

             else
                ""
            )
            (List.filterMap identity
                [ Just
                    (Ui.row "Distance"
                        (Format.signedKm 1 alongRoute
                            ++ (if alongRoute < 0 then
                                    " (behind you)"

                                else
                                    ""
                               )
                        )
                    )
                , Just (Ui.row "Climb" (Format.eleGainLoss gain loss))
                , if alongRoute /= 0 then
                    Just (Ui.row "Climbing rate" (Format.climbRate (gain / abs alongRoute * 1000)))

                  else
                    Nothing
                , Maybe.map2
                    (\distanceShare climbShare ->
                        Ui.row "Share of route" (Format.percent distanceShare ++ " of distance · " ++ Format.percent climbShare ++ " of climbing")
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
                , Just (Ui.row "Waypoints between" (String.fromInt waypointsBetween))
                ]
            )
        ]


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



-- PACE VIEW


{-| The speed an estimate runs at, in metres per second, or Nothing when the tab has not been
given enough to work one out.
-}
paceMetresPerSecond : State -> Maybe Float
paceMetresPerSecond state =
    case state.pace.activePaceSource of
        SetSpeed ->
            ifPositive (state.pace.speedKmh / 3.6)

        _ ->
            elapsedSoFar state |> Maybe.andThen (averageSoFar state)


{-| The ride's average speed so far: how much route is behind the rider, over how long it has
taken them to cover it.

Measured to where they are now rather than to the tab's chosen start point, because how fast
the ride has been going is a fact about the ride and not about a point picked out of a
dropdown. What it yields is an *elapsed* speed, stops and all — which is what an arrival
estimate wants, rather than the moving average a bike computer shows.

Both halves have to be real: at the route's start, or before the clock has moved, there is
nothing to divide.

-}
averageSoFar : State -> Float -> Maybe Float
averageSoFar state elapsedSeconds =
    Maybe.map2 (/)
        (state.position |> Maybe.andThen ifPositive)
        (ifPositive elapsedSeconds)


{-| How long the ride has taken so far, however the tab is being told: typed in as a duration,
or counted from the moment the rider set off. A set speed is not told at all.
-}
elapsedSoFar : State -> Maybe Float
elapsedSoFar state =
    case state.pace.activePaceSource of
        SetSpeed ->
            Nothing

        FromElapsed ->
            Just state.pace.elapsedAtStartSec

        FromRideStart ->
            elapsedSinceRideStart state


{-| The time between the moment the rider set off and now, in seconds.

Both are read as local wall-clock time and differenced, which is exact unless the clocks go
forward or back between the two — a twice-a-year hour that Elm cannot see, because `Time.Zone`
will convert an instant to local parts but will not tell you the offset it used.

-}
elapsedSinceRideStart : State -> Maybe Float
elapsedSinceRideStart state =
    Maybe.map2
        (\setOff now -> toFloat (Wallclock.civilSeconds (Wallclock.localDateTime state.zone now) - Wallclock.civilSeconds setOff))
        (Wallclock.parseLocalDateTime state.pace.rideStart)
        state.now


ifPositive : Float -> Maybe Float
ifPositive value =
    if value > 0 then
        Just value

    else
        Nothing


viewPaceTab : State -> Zipper EditableTrack -> Html Msg
viewPaceTab state tracks =
    let
        pace =
            state.pace

        selectable =
            selectableWaypoints state tracks.current

        waypointFor =
            selectedWaypointFor state tracks.current selectable

        body =
            case ( waypointFor pace.start, waypointFor pace.end ) of
                ( Just start, Just end ) ->
                    viewPaceEstimate state start end

                ( Nothing, _ ) ->
                    [ Ui.noticePanel (unresolvedPointNotice pace.start "Choose a start point.") ]

                ( _, Nothing ) ->
                    [ Ui.noticePanel (unresolvedPointNotice pace.end "Choose an end point.") ]
    in
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.75em"
        , Html.Attributes.style "padding" "0.5em"
        ]
        (viewPaceControls (state.position /= Nothing) pace selectable :: body)


viewPaceControls : Bool -> PaceOptions -> List ( Int, GpxApi.Waypoint ) -> Html Msg
viewPaceControls hasPosition pace selectable =
    let
        pointSelector onSelect =
            viewPointSelector { onSelect = onSelect, hasPosition = hasPosition, offerRouteEnds = True } selectable

        sourceItem source =
            Dropdown.Item (formatPaceSource source) (paceSourceName source) True

        numberInput attributes value change =
            Html.input
                (Html.Attributes.type_ "number"
                    :: Html.Attributes.min "0"
                    :: Html.Attributes.value value
                    :: Html.Events.onInput change
                    :: attributes
                )
                []
    in
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-wrap" "wrap"
        , Html.Attributes.style "gap" "1em"
        , Html.Attributes.style "align-items" "flex-end"
        ]
        [ Ui.labelledControl "Start" (pointSelector SetPaceStart pace.start)
        , Ui.labelledControl "End" (pointSelector SetPaceEnd pace.end)
        , Ui.labelledControl "Pace from"
            (Dropdown.dropdown
                (Dropdown.Options
                    [ sourceItem SetSpeed, sourceItem FromRideStart, sourceItem FromElapsed ]
                    Nothing
                    (Maybe.andThen parsePaceSource >> Maybe.map SetPaceSource >> Maybe.withDefault Ignore)
                )
                []
                (Just (formatPaceSource pace.activePaceSource))
            )
        , case pace.activePaceSource of
            SetSpeed ->
                Ui.labelledControl "Speed (km/h)"
                    (numberInput
                        [ Html.Attributes.step "0.5", Html.Attributes.style "width" "6em" ]
                        (String.fromFloat pace.speedKmh)
                        (String.toFloat >> Maybe.withDefault 0 >> UpdatePaceSpeed)
                    )

            FromRideStart ->
                Ui.labelledControl "Set off at"
                    (Html.input
                        [ Html.Attributes.type_ "datetime-local"
                        , Html.Attributes.value pace.rideStart
                        , Html.Events.onInput UpdatePaceRideStart
                        ]
                        []
                    )

            FromElapsed ->
                viewElapsedInput numberInput pace.elapsedAtStartSec
        ]


{-| Hours and minutes as two plain number boxes rather than a native time control: a time of
day stops at 23:59, and a ride that runs past a day is exactly the kind this tab is for.
-}
viewElapsedInput : (List (Html.Attribute Msg) -> String -> (String -> Msg) -> Html Msg) -> Float -> Html Msg
viewElapsedInput numberInput elapsedSec =
    let
        totalMinutes =
            round (elapsedSec / 60)

        part label value change =
            Ui.labelledControl label
                (numberInput
                    [ Html.Attributes.style "width" "4.5em" ]
                    (String.fromInt value)
                    (String.toInt >> Maybe.withDefault 0 >> change >> UpdatePaceElapsed)
                )
    in
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "gap" "0.5em"
        , Html.Attributes.style "align-items" "flex-end"
        ]
        [ part "Time so far (h)" (totalMinutes // 60) (\hours -> toFloat ((hours * 60 + modBy 60 totalMinutes) * 60))
        , part "(min)" (modBy 60 totalMinutes) (\minutes -> toFloat ((totalMinutes // 60 * 60 + minutes) * 60))
        ]


paceSourceName : PaceSource -> String
paceSourceName source =
    case source of
        SetSpeed ->
            "Set speed"

        FromRideStart ->
            "When I set off"

        FromElapsed ->
            "Time so far"


{-| The figures themselves, or the one thing standing in the way of working them out. Each
notice names what is missing rather than leaving an empty tab, because every one of them is
something the rider can put right from the controls above.
-}
viewPaceEstimate : State -> GpxApi.Waypoint -> GpxApi.Waypoint -> List (Html Msg)
viewPaceEstimate state start end =
    let
        distanceToGo =
            end.distance - start.distance
    in
    if distanceToGo <= 0 then
        [ Ui.noticePanel
            ("“"
                ++ waypointDisplayName end
                ++ "” is not ahead of “"
                ++ waypointDisplayName start
                ++ "”, so there is no arrival to estimate. Choose an end point further along the route."
            )
        ]

    else
        case paceMetresPerSecond state of
            Nothing ->
                [ Ui.noticePanel (noPaceNotice state) ]

            Just speed ->
                [ viewPaceCard state speed
                , viewArrivalCard state start end distanceToGo (distanceToGo / speed)
                ]


noPaceNotice : State -> String
noPaceNotice state =
    case state.pace.activePaceSource of
        SetSpeed ->
            "Set a speed above zero to estimate an arrival."

        FromElapsed ->
            rideSoFarNotice state "Enter how long the ride has taken so far."

        FromRideStart ->
            rideSoFarNotice state
                (case Wallclock.parseLocalDateTime state.pace.rideStart of
                    Nothing ->
                        "Give the date and time you set off and the pace will follow the clock from there."

                    Just _ ->
                        "No time has passed since you set off yet."
                )


{-| A pace read off the ride so far can fail for want of either half of it, and the distance is
worth answering for first: with no idea how far along the route the rider is there is no ride
so far to average, whatever the clock says.
-}
rideSoFarNotice : State -> String -> String
rideSoFarNotice state timeProblem =
    case state.position of
        Nothing ->
            "A pace worked out from the ride so far needs to know how far along the route you are. Set a position with the Position slider in the options panel, or start tracking."

        Just position ->
            if position <= 0 then
                "A pace worked out from the ride so far needs some route behind you to average over."

            else
                timeProblem


viewPaceCard : State -> Float -> Html Msg
viewPaceCard state speed =
    Ui.card (Ui.cardHeading [] [ Html.text "Pace" ])
        (Ui.row "Speed" (Format.speedKmh speed)
            :: Ui.row "Pace" (Format.paceMinPerKm speed)
            -- Says what the speed was divided out of, so a figure that looks wrong points
            -- straight at the ride it was read from.
            :: (case Maybe.map2 Tuple.pair state.position (elapsedSoFar state) of
                    Nothing ->
                        []

                    Just ( position, elapsed ) ->
                        [ Ui.note
                            ("averaged over "
                                ++ Format.km 1 position
                                ++ " in "
                                ++ Wallclock.duration elapsed
                                ++ ", stops included"
                            )
                        ]
               )
        )


viewArrivalCard : State -> GpxApi.Waypoint -> GpxApi.Waypoint -> Float -> Float -> Html Msg
viewArrivalCard state start end distanceToGo secondsToGo =
    Ui.card
        (Ui.cardHeading []
            [ Html.text "Arrival"
            , Html.span
                [ Html.Attributes.style "font-weight" "normal"
                , Html.Attributes.style "opacity" "0.75"
                ]
                [ Html.text (waypointDisplayName end) ]
            ]
        )
        (List.filterMap identity
            [ Just (Ui.row "Distance to go" (Format.km 1 distanceToGo))
            , Just (Ui.row "Climb to go" (Format.eleGainLoss (end.gain - start.gain) (end.loss - start.loss)))
            , Just (Ui.row "Time to go" (Wallclock.duration secondsToGo))
            , state.now |> Maybe.map (\now -> Ui.row "Arrives at" (Wallclock.timeOfDayAfter state.zone now secondsToGo))
            , elapsedSoFar state
                |> Maybe.map (\elapsed -> Ui.row "Elapsed at arrival" (Wallclock.duration (elapsed + secondsToGo)))
            , Just (Ui.note (arrivalAssumption state start))
            ]
        )


{-| The clock arrival counts from now, which only tells the truth if the rider is at the start
point now. Whenever they might not be — because the start is a fixed point rather than the
tracked position — the card says so out loud rather than letting a precise-looking time imply
otherwise.
-}
arrivalAssumption : State -> GpxApi.Waypoint -> String
arrivalAssumption state start =
    let
        clockNote =
            case state.now of
                Just now ->
                    " · now " ++ Wallclock.timeOfDayAfter state.zone now 0

                Nothing ->
                    ""
    in
    (case state.pace.start of
        AtRoutePosition ->
            "counted from where you are now"

        _ ->
            "counted as if you were at “" ++ waypointDisplayName start ++ "” now"
    )
        ++ clockNote



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
                                [ Html.text ("Lookbehind: " ++ Format.km 1 ep.liveLookbehind)
                                , Html.input
                                    [ Html.Attributes.type_ "range"
                                    , Html.Attributes.min "0"
                                    , Html.Attributes.max "50000"
                                    , Html.Attributes.step "500"
                                    , Html.Attributes.value <| String.fromFloat ep.liveLookbehind
                                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 2000 >> UpdateLiveLookbehind)
                                    ]
                                    []
                                , Html.text ("Lookahead: " ++ Format.km 1 ep.liveLookahead)
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

                        -- The Relative and Pace tabs' controls live in the tabs themselves,
                        -- beside the figures they drive.
                        RelativeTab ->
                            []

                        PaceTab ->
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
                                "points" ->
                                    SetSplitMode PointsMode

                                "categories" ->
                                    SetSplitMode CategoriesMode

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
                        [ Html.Attributes.value "points"
                        , Html.Attributes.selected (ep.activeSplitMode == PointsMode)
                        ]
                        [ Html.text "By points" ]
                    , Html.option
                        [ Html.Attributes.value "categories"
                        , Html.Attributes.selected (ep.activeSplitMode == CategoriesMode)
                        ]
                        [ Html.text "By category" ]
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

                PointsMode ->
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
                                    { onSelect = UpdateSplitPoint splitListPos, hasPosition = state.position /= Nothing, offerRouteEnds = False }
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

                CategoriesMode ->
                    let
                        selectable =
                            maybeFromloadableResource state.tracks
                                |> Maybe.map (.current >> selectableWaypoints state >> List.map Tuple.second)
                                |> Maybe.withDefault []

                        categoryCheckbox category =
                            let
                                selected =
                                    List.member category ep.splitCategories
                            in
                            checkbox selected
                                (SetSplitCategoryEnabled category (not selected))
                                -- The count of waypoints the category would split at, so
                                -- that ticking one is not guesswork. Counted against the
                                -- same selectable set the split itself uses, so a category
                                -- whose waypoints are all filtered out reads as the 0
                                -- splits it would produce.
                                ((if category == unknownCategory then
                                    "unknown"

                                  else
                                    category
                                 )
                                    ++ " ("
                                    ++ String.fromInt (List.length (List.filter (inAnyCategory [ category ]) selectable))
                                    ++ ")"
                                )
                    in
                    [ Html.fieldset [] (List.map categoryCheckbox (Dict.keys state.filteredCategories)) ]
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
                    , Html.text (Format.km 0 interval)
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
                Just "to point" ->
                    UpdateTotalDistanceDisplay (Just (ToPoint defaultRef))

                Just "from point" ->
                    UpdateTotalDistanceDisplay (Just (FromPoint defaultRef))

                _ ->
                    maybeStr
                        |> Maybe.map parseTotalDistanceDisplay
                        |> Maybe.withDefault Nothing
                        |> UpdateTotalDistanceDisplay

        modeItem mode =
            Dropdown.Item (formatTotalDistanceDisplayMode mode) (formatTotalDistanceDisplayMode mode) True

        pointSelector ref =
            [ viewPointSelector
                { onSelect = UpdateSelectedPoint, hasPosition = state.position /= Nothing, offerRouteEnds = False }
                indexedFiltered
                ref
            ]
    in
    optionGroup "Total distance"
        ([ Dropdown.dropdown
            (Dropdown.Options
                [ modeItem FromZero
                , modeItem ToFinish
                , modeItem ToDistance
                , modeItem (ToPoint defaultRef)
                , modeItem (FromPoint defaultRef)
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
                    ToDistance ->
                        [ Html.p []
                            [ Html.input
                                [ Html.Attributes.type_ "number"
                                , Html.Attributes.min "0"
                                , maxDistance |> Maybe.map (String.fromFloat >> Html.Attributes.max) |> Maybe.withDefault (Html.Attributes.disabled True)
                                , Html.Attributes.value <| String.fromFloat cs.referenceDistance
                                , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1000 >> UpdateReferenceDistance)
                                ]
                                []
                            ]
                        ]

                    ToPoint ref ->
                        pointSelector ref

                    FromPoint ref ->
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
        "Unnamed waypoint (" ++ Format.km 1 waypoint.distance ++ ")"

    else
        waypoint.name


{-| The one control for picking a point on the route. Offers the given waypoints plus the
rider's position, the latter disabled — rather than hidden — when no position is set, so the
option stays discoverable and the list does not change shape as a fix comes and goes.

`offerRouteEnds` adds the route's own two ends, in route order around the waypoints. Only the
flows that compare two arbitrary points want them: a split there is dropped by
`splitDistances` as it sits on a route end, and a cuesheet total measured to one is what
`ToFinish` and `FromZero` already say.

-}
viewPointSelector : { onSelect : PointRef -> Msg, hasPosition : Bool, offerRouteEnds : Bool } -> List ( Int, GpxApi.Waypoint ) -> PointRef -> Html Msg
viewPointSelector { onSelect, hasPosition, offerRouteEnds } indexed selected =
    let
        routeEndItem ref name =
            if offerRouteEnds then
                [ Dropdown.Item (formatPointRef ref) name True ]

            else
                []
    in
    Dropdown.dropdown
        (Dropdown.Options
            (List.concat
                [ [ Dropdown.Item (formatPointRef AtRoutePosition) routePositionName hasPosition ]
                , routeEndItem AtRouteStart routeStartName
                , List.map
                    (\( idx, wp ) ->
                        Dropdown.Item (formatPointRef (AtWaypoint idx)) (waypointDisplayName wp ++ " (" ++ Format.km 1 wp.distance ++ ")") True
                    )
                    indexed
                , routeEndItem AtRouteEnd routeEndName
                ]
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

        "to distance" ->
            Just ToDistance

        "% progress" ->
            Just PercentProgress

        "% remaining" ->
            Just PercentRemaining

        "hide" ->
            Just None

        _ ->
            -- The two point-referring modes store which point after a colon, written by
            -- formatPointRef
            case String.split ":" v of
                [ mode, refStr ] ->
                    parsePointRef refStr
                        |> Maybe.andThen
                            (\ref ->
                                if mode == "to point" then
                                    Just (ToPoint ref)

                                else if mode == "from point" then
                                    Just (FromPoint ref)

                                else
                                    Nothing
                            )

                _ ->
                    Nothing


{-| The stored form of a display mode, including which point it refers to.
-}
formatTotalDistanceDisplay : TotalDistanceDisplay -> String
formatTotalDistanceDisplay v =
    case v of
        ToPoint ref ->
            formatTotalDistanceDisplayMode v ++ ":" ++ formatPointRef ref

        FromPoint ref ->
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

        ToDistance ->
            "to distance"

        ToPoint _ ->
            "to point"

        FromPoint _ ->
            "from point"

        PercentProgress ->
            "% progress"

        PercentRemaining ->
            "% remaining"

        None ->
            "hide"


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

        "pace" ->
            Just PaceTab

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

        PaceTab ->
            "pace"


parsePaceSource : String -> Maybe PaceSource
parsePaceSource s =
    case s of
        "speed" ->
            Just SetSpeed

        "elapsed" ->
            Just FromElapsed

        "rideStart" ->
            Just FromRideStart

        _ ->
            Nothing


formatPaceSource : PaceSource -> String
formatPaceSource source =
    case source of
        SetSpeed ->
            "speed"

        FromElapsed ->
            "elapsed"

        FromRideStart ->
            "rideStart"



-- ENCODE/DECODE STATE


encodeEditableTrack : EditableTrack -> Json.Encode.Value
encodeEditableTrack track =
    Json.Encode.object
        [ ( "trackpoints", GpxApi.encodeStoredTrackpoints track.trackpoints )
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

        pace =
            state.pace
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

                        PointsMode ->
                            "points"

                        CategoriesMode ->
                            "categories"
                    )
                )
            , Just ( "splitEquidistantCount", Json.Encode.int ep.splitEquidistantCount )
            , Just ( "splitPoints", Json.Encode.list (formatPointRef >> Json.Encode.string) ep.splitPoints )
            , Just ( "splitCategories", Json.Encode.list Json.Encode.string ep.splitCategories )
            , Just ( "liveLookahead", Json.Encode.float ep.liveLookahead )
            , Just ( "liveLookbehind", Json.Encode.float ep.liveLookbehind )
            , Just ( "labelHeightGain", Json.Encode.float ep.labelHeightGain )
            , ep.distanceMarkerInterval |> Maybe.map (\m -> ( "distanceMarkerInterval", Json.Encode.float m ))
            , Just ( "distanceMarkerSegmentEnds", Json.Encode.bool ep.distanceMarkerSegmentEnds )
            , Just ( "totalDistanceDisplay", Json.Encode.string (formatTotalDistanceDisplay cs.totalDistanceDisplay) )
            , Just ( "referenceDistance", Json.Encode.float cs.referenceDistance )
            , Just ( "itemSpacing", Json.Encode.int cs.itemSpacing )
            , Just ( "distanceDetail", Json.Encode.int cs.distanceDetail )
            , Just ( "showStartFinish", Json.Encode.bool cs.showStartFinish )
            , Just ( "offRouteThreshold", Json.Encode.float state.offRouteThreshold )
            , Just ( "showOffRouteWaypoints", Json.Encode.bool state.showOffRouteWaypoints )
            , Just ( "showOffRouteDistance", Json.Encode.bool state.showOffRouteDistance )
            , Just ( "relativeStart", Json.Encode.string (formatPointRef rel.start) )
            , Just ( "relativeEnd", Json.Encode.string (formatPointRef rel.end) )
            , Just ( "relativeStartCollapsed", Json.Encode.bool rel.startCollapsed )
            , Just ( "relativeEndCollapsed", Json.Encode.bool rel.endCollapsed )
            , Just ( "paceStart", Json.Encode.string (formatPointRef pace.start) )
            , Just ( "paceEnd", Json.Encode.string (formatPointRef pace.end) )
            , Just ( "paceSource", Json.Encode.string (formatPaceSource pace.activePaceSource) )
            , Just ( "paceSpeedKmh", Json.Encode.float pace.speedKmh )
            , Just ( "paceElapsedSec", Json.Encode.float pace.elapsedAtStartSec )
            , Just ( "paceRideStart", Json.Encode.string pace.rideStart )
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

        defPace =
            defaultPaceOptions
    in
    Json.Decode.succeed
        (\tracks activeTab showOptions trackingIntervalSec categoryFilterEnabled filteredCategories fontSize trackHeight trackThickness showIntensity intensityTau position viewMode splitMode splitEquidistantCount splitPoints splitCategories liveLookahead liveLookbehind labelHeightGain distanceMarkerInterval distanceMarkerSegmentEnds totalDistanceDisplay referenceDistance itemSpacing distanceDetail showStartFinish showOffRouteDistance offRouteThreshold showOffRouteWaypoints relativeStart relativeEnd relativeStartCollapsed relativeEndCollapsed paceStart paceEnd paceSource paceSpeedKmh paceElapsedSec paceRideStart ->
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
                        Just "points" ->
                            PointsMode

                        Just "categories" ->
                            CategoriesMode

                        _ ->
                            EquidistantMode
                , splitEquidistantCount = splitEquidistantCount |> Maybe.withDefault 1
                , splitPoints = splitPoints |> Maybe.withDefault [] |> List.filterMap parsePointRef
                , splitCategories = splitCategories |> Maybe.withDefault defEp.splitCategories
                , liveLookahead = liveLookahead |> Maybe.withDefault defEp.liveLookahead
                , liveLookbehind = liveLookbehind |> Maybe.withDefault defEp.liveLookbehind
                , labelHeightGain = labelHeightGain |> Maybe.withDefault defEp.labelHeightGain
                , distanceMarkerInterval = distanceMarkerInterval
                , distanceMarkerSegmentEnds = distanceMarkerSegmentEnds |> Maybe.withDefault defEp.distanceMarkerSegmentEnds
                }
            , cuesheet =
                { totalDistanceDisplay = totalDistanceDisplay |> Maybe.andThen parseTotalDistanceDisplay |> Maybe.withDefault defCs.totalDistanceDisplay
                , referenceDistance = referenceDistance |> Maybe.withDefault defCs.referenceDistance
                , itemSpacing = itemSpacing |> Maybe.withDefault defCs.itemSpacing
                , distanceDetail = distanceDetail |> Maybe.withDefault defCs.distanceDetail
                , showStartFinish = showStartFinish |> Maybe.withDefault defCs.showStartFinish
                }
            , relative =
                { start = relativeStart |> Maybe.andThen parsePointRef |> Maybe.withDefault defRel.start
                , end = relativeEnd |> Maybe.andThen parsePointRef |> Maybe.withDefault defRel.end
                , startCollapsed = relativeStartCollapsed |> Maybe.withDefault defRel.startCollapsed
                , endCollapsed = relativeEndCollapsed |> Maybe.withDefault defRel.endCollapsed
                }
            , pace =
                { start = paceStart |> Maybe.andThen parsePointRef |> Maybe.withDefault defPace.start
                , end = paceEnd |> Maybe.andThen parsePointRef |> Maybe.withDefault defPace.end
                , activePaceSource = paceSource |> Maybe.andThen parsePaceSource |> Maybe.withDefault defPace.activePaceSource
                , speedKmh = paceSpeedKmh |> Maybe.withDefault defPace.speedKmh
                , elapsedAtStartSec = paceElapsedSec |> Maybe.withDefault defPace.elapsedAtStartSec
                , rideStart = paceRideStart |> Maybe.withDefault defPace.rideStart
                }
            , stateDecodeError = Nothing
            , storageError = Nothing
            , splitSegments = Nothing
            , profilePixelWidth = Nothing
            , now = Nothing
            , zone = Time.utc
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
        |> andMap (maybeField "splitCategories" (Json.Decode.list Json.Decode.string))
        |> andMap (maybeField "liveLookahead" Json.Decode.float)
        |> andMap (maybeField "liveLookbehind" Json.Decode.float)
        |> andMap (maybeField "labelHeightGain" Json.Decode.float)
        |> andMap (maybeField "distanceMarkerInterval" Json.Decode.float)
        |> andMap (maybeField "distanceMarkerSegmentEnds" Json.Decode.bool)
        |> andMap (maybeField "totalDistanceDisplay" Json.Decode.string)
        |> andMap (maybeField "referenceDistance" Json.Decode.float)
        |> andMap (maybeField "itemSpacing" Json.Decode.int)
        |> andMap (maybeField "distanceDetail" Json.Decode.int)
        |> andMap (maybeField "showStartFinish" Json.Decode.bool)
        |> andMap (maybeField "showOffRouteDistance" Json.Decode.bool)
        |> andMap (maybeField "offRouteThreshold" Json.Decode.float)
        |> andMap (maybeField "showOffRouteWaypoints" Json.Decode.bool)
        |> andMap (maybeField "relativeStart" Json.Decode.string)
        |> andMap (maybeField "relativeEnd" Json.Decode.string)
        |> andMap (maybeField "relativeStartCollapsed" Json.Decode.bool)
        |> andMap (maybeField "relativeEndCollapsed" Json.Decode.bool)
        |> andMap (maybeField "paceStart" Json.Decode.string)
        |> andMap (maybeField "paceEnd" Json.Decode.string)
        |> andMap (maybeField "paceSource" Json.Decode.string)
        |> andMap (maybeField "paceSpeedKmh" Json.Decode.float)
        |> andMap (maybeField "paceElapsedSec" Json.Decode.float)
        |> andMap (maybeField "paceRideStart" Json.Decode.string)


andMap : Json.Decode.Decoder a -> Json.Decode.Decoder (a -> b) -> Json.Decode.Decoder b
andMap =
    Json.Decode.map2 (|>)



-- PORTS


port logError : String -> Cmd msg


port storeState : String -> Cmd msg


-- Reports that the browser refused to save what storeState sent: the route is
-- still usable but will not survive a reload.
port storeStateFailed : (String -> msg) -> Sub msg


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
