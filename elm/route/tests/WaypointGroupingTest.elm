module WaypointGroupingTest exposing (suite)

import Dict
import DistanceDisplay exposing (TotalDistanceDisplay(..))
import Expect
import Fuzz
import GpxApi exposing (Waypoint)
import Route exposing (PointRef(..))
import Test exposing (Test, describe, fuzz, test)
import WaypointGrouping exposing (groupWaypoints)


point : Float -> Waypoint
point distance =
    Waypoint distance "Water" [ "water" ] 12 3 7


indices : List WaypointGrouping.WaypointGroup -> List (List Int)
indices =
    List.map (.members >> List.map Tuple.first)


fixture : List Float -> List ( Int, Waypoint )
fixture =
    List.indexedMap (\index distance -> ( index, point distance ))


labelFor : TotalDistanceDisplay -> Int -> Float -> Maybe Waypoint -> Waypoint -> Maybe String
labelFor mode detail finish reference =
    DistanceDisplay.waypointLabel { totalDistanceDisplay = mode, referenceDistance = 1007, distanceDetail = detail } finish reference


suite : Test
suite =
    describe "Waypoint grouping"
        [ describe "callback contract"
            [ test "empty input" <|
                \_ -> groupWaypoints (always (Just "same")) [] |> Expect.equal []
            , test "a singleton retains every value and its original index" <|
                \_ ->
                    groupWaypoints (always (Just "same")) [ ( 42, point 304 ) ]
                        |> Expect.equal [ { members = [ ( 42, point 304 ) ], distance = 304, gain = 12, loss = 3 } ]
            , test "the callback groups even widely separated distances, without reordering" <|
                \_ ->
                    groupWaypoints (always (Just "same")) [ ( 9, point 900 ), ( 2, point 10 ), ( 7, point 300 ) ]
                        |> Expect.equal
                            [ { members = [ ( 9, point 900 ), ( 2, point 10 ), ( 7, point 300 ) ], distance = 900, gain = 12, loss = 3 } ]
            , test "equal distances with differing labels stay separate" <|
                \_ ->
                    groupWaypoints (.name >> Just)
                        [ ( 5, point 300 ), ( 8, Waypoint 300 "Camp" [] 20 4 0 ) ]
                        |> indices
                        |> Expect.equal [ [ 5 ], [ 8 ] ]
            , test "matching labels only join consecutive runs" <|
                \_ ->
                    groupWaypoints (.name >> Just)
                        [ ( 5, point 300 ), ( 8, Waypoint 300 "Camp" [] 20 4 0 ), ( 9, point 300 ) ]
                        |> indices
                        |> Expect.equal [ [ 5 ], [ 8 ], [ 9 ] ]
            , test "Nothing breaks a run and consecutive Nothing values never group" <|
                \_ ->
                    groupWaypoints
                        (\wp ->
                            if wp.distance == 300 then
                                Just "same"

                            else
                                Nothing
                        )
                        (fixture [ 300, 304, 305, 300, 300 ])
                        |> indices
                        |> Expect.equal [ [ 0 ], [ 1 ], [ 2 ], [ 3, 4 ] ]
            , test "an explicitly supplied empty string is still a label" <|
                \_ -> groupWaypoints (always (Just "")) (fixture [ 300, 304 ]) |> indices |> Expect.equal [ [ 0, 1 ] ]
            , fuzz (Fuzz.list Fuzz.int) "flattening groups preserves the entire ordered input" <|
                \distances ->
                    let
                        members =
                            fixture (List.map toFloat distances)
                    in
                    groupWaypoints (DistanceDisplay.fromStartLabel 2) members
                        |> List.concatMap .members
                        |> Expect.equal members
            ]
        , describe "real display labels"
            (List.indexedMap
                (\index ( detail, distances, expected ) ->
                    test ("RFC rounding case " ++ String.fromInt index) <|
                        \_ ->
                            groupWaypoints (labelFor FromZero detail 1000 Nothing) (fixture distances)
                                |> indices
                                |> Expect.equal expected
                )
                [ ( 2, [ 300, 304 ], [ [ 0, 1 ] ] )
                , ( 3, [ 300, 304 ], [ [ 0 ], [ 1 ] ] )
                , ( 2, [ 304, 306 ], [ [ 0 ], [ 1 ] ] )
                , ( 2, [ 300, 304, 308 ], [ [ 0, 1 ], [ 2 ] ] )
                , ( 0, [ 499, 500, 501 ], [ [ 0 ], [ 1, 2 ] ] )
                , ( 1, [ 349, 350, 351 ], [ [ 0 ], [ 1, 2 ] ] )
                , ( 2, [ 304.9, 305, 305.1 ], [ [ 0 ], [ 1, 2 ] ] )
                , ( 3, [ 300.4, 300.5, 300.6 ], [ [ 0 ], [ 1, 2 ] ] )
                ]
                ++ [ test "changing detail splits and regroups without changing identities" <|
                        \_ ->
                            List.map (\detail -> groupWaypoints (labelFor FromZero detail 1000 Nothing) [ ( 7, point 300 ), ( 2, point 304 ) ] |> indices) [ 2, 3, 2 ]
                                |> Expect.equal [ [ [ 7, 2 ] ], [ [ 7 ], [ 2 ] ], [ [ 7, 2 ] ] ]
                   , test "a changed distance origin shifts rounding boundaries" <|
                        \_ ->
                            List.map (\mode -> groupWaypoints (labelFor mode 2 1007 Nothing) (fixture [ 300, 304 ]) |> indices) [ FromZero, ToFinish, ToDistance ]
                                |> Expect.equal [ [ [ 0, 1 ] ], [ [ 0 ], [ 1 ] ], [ [ 0 ], [ 1 ] ] ]
                   , test "point reference modes use the resolved reference" <|
                        \_ ->
                            List.map (\mode -> labelFor mode 2 1000 (Just (point 500)) (point 304)) [ ToPoint (AtWaypoint 3), FromPoint (AtWaypoint 3) ]
                                |> Expect.equal [ Just "0.20km", Just "-0.20km" ]
                   , test "percentage groups use the rendered precision, independently of kilometre detail" <|
                        \_ ->
                            List.map (\mode -> groupWaypoints (labelFor mode 3 1000 Nothing) (fixture [ 300, 304 ]) |> indices) [ PercentProgress, PercentRemaining ]
                                |> Expect.equal [ [ [ 0, 1 ] ], [ [ 0, 1 ] ] ]
                   , test "missing references, hidden distances and empty-route percentages stay ungrouped" <|
                        \_ ->
                            List.map (\mode -> groupWaypoints (labelFor mode 2 0 Nothing) (fixture [ 300, 304 ]) |> indices)
                                [ ToPoint (AtWaypoint 2), FromPoint AtRoutePosition, None, PercentProgress, PercentRemaining ]
                                |> Expect.equal (List.repeat 5 [ [ 0 ], [ 1 ] ])
                   , test "the exact reference point suppresses its label and breaks a run" <|
                        \_ ->
                            groupWaypoints (labelFor (FromPoint (AtWaypoint 2)) 2 1000 (Just (point 300))) (fixture [ 300, 300, 304 ])
                                |> indices
                                |> Expect.equal [ [ 0 ], [ 1 ], [ 2 ] ]
                   , test "pickers retain a zero from-start label" <|
                        \_ ->
                            groupWaypoints (DistanceDisplay.fromStartLabel 2) (fixture [ 0, 4 ]) |> indices |> Expect.equal [ [ 0, 1 ] ]
                   ]
            )
        , describe "headings"
            [ test "duplicate names are deduplicated without losing members" <|
                \_ ->
                    groupWaypoints (always (Just "same")) [ ( 0, point 300 ), ( 1, point 304 ), ( 2, Waypoint 304 "Camp" [] 0 0 0 ) ]
                        |> List.map (\group -> ( WaypointGrouping.label group, List.length group.members ))
                        |> Expect.equal [ ( "Water · Camp", 3 ) ]
            , test "blank names get a count fallback" <|
                \_ ->
                    groupWaypoints (always (Just "same")) [ ( 0, Waypoint 300 " " [] 0 0 0 ), ( 1, Waypoint 304 "" [] 0 0 0 ) ]
                        |> List.map WaypointGrouping.label
                        |> Expect.equal [ "2 waypoints" ]
            ]
        , test "effective input excludes deleted/filtered members and respects distance overrides with stable indices" <|
            \_ ->
                Route.editableTrackFromGpxTrack
                    (GpxApi.Track
                        [ GpxApi.TrackPoint 0 0 0 0 0 0, GpxApi.TrackPoint 1000 20 0 0 20 0 ]
                        [ point 300, point 302, Waypoint 303 "Camp" [ "camp" ] 0 0 0, point 800 ]
                        20
                        0
                    )
                    |> (\track ->
                            { track
                                | editableWaypoints =
                                    List.indexedMap
                                        (\i wp ->
                                            if i == 1 then
                                                { wp | deleted = True }

                                            else
                                                wp
                                        )
                                        track.editableWaypoints
                            }
                       )
                    |> (\track -> Route.updateEditableWaypoint track 3 (Route.updateOverrides (\o -> { o | distance = Just 304 })))
                    |> Route.selectableWaypoints [ Route.categoryPredicate (Dict.fromList [ ( "camp", False ) ]) ]
                    |> List.sortBy (Tuple.second >> .distance)
                    |> groupWaypoints (DistanceDisplay.fromStartLabel 2)
                    |> List.map (\group -> ( List.map Tuple.first group.members, List.map (Tuple.second >> .distance) group.members ))
                    |> Expect.equal [ ( [ 0, 3 ], [ 300, 304 ] ) ]
        ]
