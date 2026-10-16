module RouteTest exposing (suite)

import Dict
import Expect
import GpxApi
import Json.Decode
import Json.Encode
import Route exposing (PointRef(..))
import Test exposing (Test, describe, test)
import Zipper


suite : Test
suite =
    describe "Route"
        [ storageTests
        , editTests
        , pointTests
        , selectionTests
        ]


trackpoints : List GpxApi.TrackPoint
trackpoints =
    [ GpxApi.TrackPoint 0 100 51 -1 0 0
    , GpxApi.TrackPoint 1000 120 51.1 -1.1 40 20
    , GpxApi.TrackPoint 2000 90 51.2 -1.2 70 80
    ]


water : GpxApi.Waypoint
water =
    GpxApi.Waypoint 500 "Water" [ "Water" ] 20 5 15


camp : GpxApi.Waypoint
camp =
    GpxApi.Waypoint 1500 "Camp" [ "Campground" ] 50 40 30


editedTrack : Route.EditableTrack
editedTrack =
    { trackpoints = trackpoints
    , editableWaypoints =
        [ Route.EditableWaypoint water False False Route.emptyOverrides
        , Route.EditableWaypoint (GpxApi.Waypoint 1000 "Deleted" [] 40 20 0) True False Route.emptyOverrides
        , Route.EditableWaypoint camp
            False
            True
            { name = Just "Moved camp", distance = Just 1800, categories = Just [] }
        ]
    , gain = 70
    , loss = 80
    }


{-| Literal fixtures guard the existing saved format independently of the encoder. Before
the compact encoding, trackpoints used the WASM field names. Older waypoints omit `created`.
-}
legacyTrackJson : String
legacyTrackJson =
    """{"trackpoints":[{"dist":1000,"ele":120,"lat":51.1,"lon":-1.1,"gain":40,"loss":20}],"editableWaypoints":[{"original":{"dist":500,"name":"Water","categories":["Water"],"gain":20,"loss":5,"offRoute":15},"deleted":true}],"gain":70,"loss":80}"""


compactTrackJson : String
compactTrackJson =
    """{"trackpoints":[[1000,120,51.1,-1.1,40,20]],"editableWaypoints":[{"original":{"dist":500,"name":"Water","categories":["Water"],"gain":20,"loss":5,"offRoute":15},"deleted":true}],"gain":70,"loss":80}"""


storedTrack : Route.EditableTrack
storedTrack =
    { trackpoints = [ GpxApi.TrackPoint 1000 120 51.1 -1.1 40 20 ]
    , editableWaypoints = [ Route.EditableWaypoint water True False Route.emptyOverrides ]
    , gain = 70
    , loss = 80
    }


storageTests : Test
storageTests =
    describe "saved tracks"
        [ test "reads the older named-field trackpoints and defaults missing created flags" <|
            \_ -> Json.Decode.decodeString Route.editableTrackDecoder legacyTrackJson |> Expect.equal (Ok storedTrack)
        , test "reads the compact saved format" <|
            \_ -> Json.Decode.decodeString Route.editableTrackDecoder compactTrackJson |> Expect.equal (Ok storedTrack)
        , test "writes the existing compact JSON shape and omits absent overrides" <|
            \_ -> Route.encodeEditableTrack storedTrack |> Json.Encode.encode 0 |> Expect.equal compactTrackJson
        , test "preserves original waypoints, deletion, creation, and every override through a save" <|
            \_ ->
                Route.encodeEditableTrack editedTrack
                    |> Json.Decode.decodeValue Route.editableTrackDecoder
                    |> Expect.equal (Ok editedTrack)
        , test "an explicitly empty name or category list is preserved as an edit" <|
            \_ ->
                Route.updateEditableWaypoint editedTrack 0 (Route.updateOverrides (\overrides -> { overrides | name = Just "", categories = Just [] }))
                    |> (\track ->
                            Route.encodeEditableTrack track
                                |> Json.Decode.decodeValue Route.editableTrackDecoder
                                |> Expect.equal (Ok track)
                       )
        , test "saved coordinates keep the existing precision limits" <|
            \_ ->
                Route.encodeEditableTrack
                    { editedTrack | trackpoints = [ GpxApi.TrackPoint 123.456 78.945 51.12345678 -1.12345678 12.345 6.789 ] }
                    |> Json.Decode.decodeValue (Json.Decode.field "trackpoints" (Json.Decode.list (Json.Decode.list Json.Decode.float)))
                    |> Expect.equal (Ok [ [ 123.5, 78.9, 51.123457, -1.123457, 12.3, 6.8 ] ])
        , test "all tracks and the current selection survive a zipper save" <|
            \_ ->
                Zipper.encode Route.encodeEditableTrack (Zipper.Zipper [ storedTrack ] editedTrack [ storedTrack ])
                    |> Json.Decode.decodeValue (Zipper.decoder Route.editableTrackDecoder)
                    |> Expect.equal (Ok (Zipper.Zipper [ storedTrack ] editedTrack [ storedTrack ]))
        , test "an empty track can still be saved and restored" <|
            \_ ->
                Route.encodeEditableTrack (Route.EditableTrack [] [] 0 0)
                    |> Json.Decode.decodeValue Route.editableTrackDecoder
                    |> Expect.equal (Ok (Route.EditableTrack [] [] 0 0))
        , test "a track missing required totals is rejected" <|
            \_ -> Json.Decode.decodeString Route.editableTrackDecoder "{\"trackpoints\":[],\"editableWaypoints\":[]}" |> Expect.err
        ]


editTests : Test
editTests =
    describe "effective waypoint edits"
        [ test "a GPX upload starts with unedited waypoints and the supplied route totals" <|
            \_ ->
                Route.editableTrackFromGpxTrack (GpxApi.Track trackpoints [ water, camp ] 70 80)
                    |> Expect.equal
                        (Route.EditableTrack trackpoints
                            [ Route.EditableWaypoint water False False Route.emptyOverrides
                            , Route.EditableWaypoint camp False False Route.emptyOverrides
                            ]
                            70
                            80
                        )
        , test "an unedited waypoint retains its original off-route and elevation data" <|
            \_ ->
                Route.effectiveWaypoint trackpoints (Route.EditableWaypoint water False False Route.emptyOverrides)
                    |> Expect.equal water
        , test "moving a waypoint updates cumulative climb and puts it on the route" <|
            \_ ->
                Route.effectiveWaypoints editedTrack
                    |> Expect.equal [ water, GpxApi.Waypoint 1800 "Moved camp" [] 70 80 0 ]
        , test "a rename alone leaves the waypoint's original distance and climb intact" <|
            \_ ->
                Route.EditableWaypoint water False False { name = Just "Tap", distance = Nothing, categories = Nothing }
                    |> Route.effectiveWaypoint trackpoints
                    |> Expect.equal { water | name = "Tap" }
        , test "moving a waypoint without trackpoints retains its original climb" <|
            \_ ->
                Route.EditableWaypoint water False False { name = Nothing, distance = Just 800, categories = Nothing }
                    |> Route.effectiveWaypoint []
                    |> Expect.equal { water | distance = 800, offRoute = 0 }
        , test "an empty name has a useful display fallback" <|
            \_ -> Route.waypointDisplayName { water | name = "  " } |> Expect.equal "Unnamed waypoint (0.5km)"
        ]


pointTests : Test
pointTests =
    describe "point references"
        (List.map
            (\( ref, stored ) ->
                test ("keeps the stored point reference " ++ stored) <|
                    \_ -> ( Route.formatPointRef ref, Route.parsePointRef stored ) |> Expect.equal ( stored, Just ref )
            )
            [ ( AtWaypoint 2, "2" ), ( AtRoutePosition, "position" ), ( AtRouteStart, "start" ), ( AtRouteEnd, "end" ) ]
            ++ [ test "unknown reference strings are rejected" <|
                    \_ -> Route.parsePointRef "waypoint" |> Expect.equal Nothing
               , test "waypoint references use original indices, including deleted entries" <|
                    \_ ->
                        Route.resolvePointRef Nothing Nothing editedTrack (AtWaypoint 2)
                            |> Expect.equal (Just (GpxApi.Waypoint 1800 "Moved camp" [] 70 80 0))
               , test "a deleted waypoint no longer resolves" <|
                    \_ -> Route.resolvePointRef Nothing Nothing editedTrack (AtWaypoint 1) |> Expect.equal Nothing
               , test "an out-of-range waypoint no longer resolves" <|
                    \_ -> Route.resolvePointRef Nothing Nothing editedTrack (AtWaypoint 10) |> Expect.equal Nothing
               , test "an unset position does not resolve" <|
                    \_ -> Route.resolvePointRef Nothing Nothing editedTrack AtRoutePosition |> Expect.equal Nothing
               , test "a manual position uses route climb with no off-route distance" <|
                    \_ ->
                        Route.resolvePointRef (Just 750) Nothing editedTrack AtRoutePosition
                            |> Expect.equal (Just (GpxApi.Waypoint 750 "Position on route" [] 40 20 0))
               , test "a GPS position carries the gap from its fix to the route" <|
                    \_ ->
                        Route.resolvePointRef (Just 750)
                            (Just { position = { lat = 51, lon = -1 }, accuracy = 5, matchedDistance = 750, offRouteDistance = 123, altitude = Just 999 })
                            editedTrack
                            AtRoutePosition
                            |> Expect.equal (Just (GpxApi.Waypoint 750 "Position on route" [] 40 20 123))
               , test "route ends resolve even without waypoints or a current position" <|
                    \_ ->
                        List.map (Route.resolvePointRef Nothing Nothing { editedTrack | editableWaypoints = [] }) [ AtRouteStart, AtRouteEnd ]
                            |> Expect.equal
                                [ Just (GpxApi.Waypoint 0 "Start of route" [] 0 0 0)
                                , Just (GpxApi.Waypoint 2000 "End of route" [] 70 80 0)
                                ]
               , test "an empty track cannot supply a position's cumulative climb" <|
                    \_ -> Route.resolvePointRef (Just 750) Nothing { editedTrack | trackpoints = [] } AtRoutePosition |> Expect.equal Nothing
               , test "a position beyond the last sample uses the last sample's climb" <|
                    \_ -> Route.cumulativeGainLossAtDistance 2500 trackpoints |> Expect.equal (Ok ( 70, 80 ))
               , test "removing a waypoint shifts only later waypoint indices" <|
                    \_ ->
                        List.map (Route.shiftPointRef 1) [ AtWaypoint 0, AtWaypoint 2, AtRoutePosition, AtRouteStart, AtRouteEnd ]
                            |> Expect.equal [ AtWaypoint 0, AtWaypoint 1, AtRoutePosition, AtRouteStart, AtRouteEnd ]
               , test "split point references sort by their resolved route distances" <|
                    \_ ->
                        Route.sortPointRefs (Just 750) editedTrack [ AtRouteEnd, AtWaypoint 0, AtRoutePosition, AtRouteStart ]
                            |> Expect.equal [ AtRouteStart, AtWaypoint 0, AtRoutePosition, AtRouteEnd ]
               ]
        )


selectionTests : Test
selectionTests =
    describe "selectable points"
        [ test "deletions do not renumber surviving selections" <|
            \_ -> Route.selectableWaypoints [] editedTrack |> List.map Tuple.first |> Expect.equal [ 0, 2 ]
        , test "category filtering applies to edited categories with original indices" <|
            \_ ->
                Route.selectableWaypoints [ Route.categoryPredicate (Dict.fromList [ ( "Water", False ) ]) ] editedTrack
                    |> List.map Tuple.first
                    |> Expect.equal [ 2 ]
        , test "uncategorised waypoints use the unknown-category choice" <|
            \_ ->
                Route.selectableWaypoints [ Route.categoryPredicate (Dict.fromList [ ( "", False ) ]) ] editedTrack
                    |> List.map Tuple.first
                    |> Expect.equal [ 0 ]
        , test "an unlisted category is included by default" <|
            \_ -> Route.categoryPredicate Dict.empty water |> Expect.equal True
        , test "a multi-category waypoint needs only one included category" <|
            \_ ->
                Route.categoryPredicate (Dict.fromList [ ( "Water", False ), ( "Shop", True ) ]) { water | categories = [ "Water", "Shop" ] }
                    |> Expect.equal True
        , test "off-route filtering uses the effective distance override" <|
            \_ -> Route.selectableWaypoints [ Route.offRoutePredicate 0 ] editedTrack |> List.map Tuple.first |> Expect.equal [ 2 ]
        , test "a waypoint exactly at the off-route threshold is included" <|
            \_ -> Route.offRoutePredicate 15 water |> Expect.equal True
        , test "a selected waypoint hidden by filters resolves to nothing" <|
            \_ -> Route.selectedWaypointFor Nothing Nothing editedTrack [] (AtWaypoint 0) |> Expect.equal Nothing
        , test "the selected waypoint comes from the offered list of effective waypoints" <|
            \_ ->
                Route.selectedWaypointFor Nothing Nothing editedTrack (Route.selectableWaypoints [] editedTrack) (AtWaypoint 2)
                    |> Expect.equal (Just (GpxApi.Waypoint 1800 "Moved camp" [] 70 80 0))
        , test "filters cannot hide route endpoints or a set position" <|
            \_ ->
                List.map (Route.selectedWaypointFor (Just 750) Nothing editedTrack []) [ AtRouteStart, AtRouteEnd, AtRoutePosition ]
                    |> List.map (Maybe.map .distance)
                    |> Expect.equal [ Just 0, Just 2000, Just 750 ]
        , test "the unknown category is also a valid category split choice" <|
            \_ -> Route.inAnyCategory [ "" ] { camp | categories = [] } |> Expect.equal True
        ]
