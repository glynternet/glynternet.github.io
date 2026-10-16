module Route exposing
    ( EditableTrack
    , EditableWaypoint
    , PointRef(..)
    , WaypointOverrides
    , categoryPredicate
    , cumulativeGainLossAtDistance
    , editableTrackDecoder
    , editableTrackFromGpxTrack
    , effectiveWaypoint
    , effectiveWaypoints
    , emptyOverrides
    , encodeEditableTrack
    , filterWaypoints
    , formatPointRef
    , inAnyCategory
    , indexedFilteredWaypoints
    , lastTrackpointDistance
    , offRoutePredicate
    , parsePointRef
    , refDistance
    , resolvePointRef
    , routeEndName
    , routePositionName
    , routeStartName
    , selectableWaypoints
    , selectedWaypointFor
    , shiftPointRef
    , sortPointRefs
    , trackpointAtDistance
    , unknownCategory
    , updateEditableWaypoint
    , updateOverrides
    , waypointDisplayName
    )

{-| Editable tracks and stable references to points on a route, independent of app state.

The stored track format preserves edits and deleted waypoints and uses compact trackpoint
arrays. It differs from `GpxApi.encodeTrack`, which sends effective waypoints and named
trackpoints to WASM. Keep the two formats separate.

-}

import Dict
import Format
import GpxApi
import Json.Decode
import Json.Encode
import List.Extra
import Location


type alias EditableTrack =
    { trackpoints : List GpxApi.TrackPoint
    , editableWaypoints : List EditableWaypoint
    , gain : Float
    , loss : Float
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
    , gain = track.gain
    , loss = track.loss
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
                    track.gain
                    track.loss
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


sortPointRefs : Maybe Float -> EditableTrack -> List PointRef -> List PointRef
sortPointRefs position track =
    List.sortBy (refDistance position track >> Maybe.withDefault 0)


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


filterWaypoints : List (GpxApi.Waypoint -> Bool) -> List GpxApi.Waypoint -> List GpxApi.Waypoint
filterWaypoints filters =
    List.filter (\waypoint -> List.all (\filter -> filter waypoint) filters)


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

The caller supplies selection predicates rather than the live-view window: a selection
must not disappear just because the window has moved past the waypoint it names.

-}
selectableWaypoints : List (GpxApi.Waypoint -> Bool) -> EditableTrack -> List ( Int, GpxApi.Waypoint )
selectableWaypoints predicates track =
    indexedFilteredWaypoints track
        (filterWaypoints predicates (effectiveWaypoints track))


{-| Resolves a chosen point, but only ever to a waypoint the dropdown is still offering.
Going through `selectable` rather than the whole track means a reference to one the filters
have hidden reads as "nothing chosen" instead of silently standing for something the rider
cannot see. Nothing else the dropdown offers is a waypoint of the track's, so nothing else
can be filtered away.
-}
selectedWaypointFor : Maybe Float -> Maybe Location.LocationState -> EditableTrack -> List ( Int, GpxApi.Waypoint ) -> PointRef -> Maybe GpxApi.Waypoint
selectedWaypointFor position location track selectable ref =
    case ref of
        AtWaypoint idx ->
            selectable |> List.Extra.find (\( i, _ ) -> i == idx) |> Maybe.map Tuple.second

        _ ->
            resolvePointRef position location track ref


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


{-| Waypoints can be unnamed — `AddWaypoint` creates them with an empty name — so fall back
to something that still identifies which one is meant.
-}
waypointDisplayName : GpxApi.Waypoint -> String
waypointDisplayName waypoint =
    if String.isEmpty (String.trim waypoint.name) then
        "Unnamed waypoint (" ++ Format.km 1 waypoint.distance ++ ")"

    else
        waypoint.name


encodeEditableTrack : EditableTrack -> Json.Encode.Value
encodeEditableTrack track =
    Json.Encode.object
        [ ( "trackpoints", GpxApi.encodeStoredTrackpoints track.trackpoints )
        , ( "editableWaypoints", Json.Encode.list encodeEditableWaypoint track.editableWaypoints )
        , ( "gain", Json.Encode.float track.gain )
        , ( "loss", Json.Encode.float track.loss )
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
    Json.Decode.map4 EditableTrack
        (Json.Decode.field "trackpoints" GpxApi.decodeTrackpoints)
        (Json.Decode.field "editableWaypoints" (Json.Decode.list editableWaypointDecoder))
        (Json.Decode.field "gain" Json.Decode.float)
        (Json.Decode.field "loss" Json.Decode.float)


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
