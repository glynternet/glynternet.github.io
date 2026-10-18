module ProfileSplitTest exposing (suite)

import Expect
import GpxApi
import ProfileSplit
import Route exposing (PointRef(..))
import Test exposing (Test, describe, test)


track : Route.EditableTrack
track =
    Route.editableTrackFromGpxTrack
        (GpxApi.Track
            [ GpxApi.TrackPoint 0 100 51 -1 0 0, GpxApi.TrackPoint 2000 100 51.1 -1 0 0 ]
            [ GpxApi.Waypoint 500 "Water" [] 0 0 0, GpxApi.Waypoint 1500 "Camp" [] 0 0 0 ]
            0
            0
        )


suite : Test
suite =
    describe "Profile split dependencies"
        [ describe "chosen point boundaries"
            [ test "position set, move and clear produce the boundaries that must refresh" <|
                \_ ->
                    List.map (\position -> ProfileSplit.pointDistances position track [ AtRoutePosition ]) [ Nothing, Just 750, Just 1000, Nothing ]
                        |> Expect.equal [ [], [ 750 ], [ 1000 ], [] ]
            , test "fixed waypoints do not depend on the rider's position" <|
                \_ ->
                    List.map (\position -> ProfileSplit.pointDistances position track [ AtWaypoint 1, AtWaypoint 0 ]) [ Nothing, Just 750, Just 1000 ]
                        |> Expect.equal [ [ 500, 1500 ], [ 500, 1500 ], [ 500, 1500 ] ]
            , test "clearing a duplicate position boundary does not change effective splits" <|
                \_ ->
                    List.map (\position -> ProfileSplit.pointDistances position track [ AtWaypoint 0, AtRoutePosition ]) [ Just 500, Nothing ]
                        |> Expect.equal [ [ 500 ], [ 500 ] ]
            , test "route ends and positions on or beyond them do not create empty segments" <|
                \_ ->
                    List.map (\position -> ProfileSplit.pointDistances position track [ AtRouteStart, AtRouteEnd, AtRoutePosition ]) [ Just 0, Just 2000, Just 3000, Just -1 ]
                        |> Expect.equal [ [], [], [], [] ]
            , test "deleted and missing waypoints do not become boundaries" <|
                \_ ->
                    ProfileSplit.pointDistances Nothing (Route.updateEditableWaypoint track 0 (\waypoint -> { waypoint | deleted = True })) [ AtWaypoint 0, AtWaypoint 1, AtWaypoint 9 ]
                        |> Expect.equal [ 1500 ]
            , test "distance overrides determine effective boundaries" <|
                \_ ->
                    ProfileSplit.pointDistances Nothing
                        (Route.updateEditableWaypoint track 0 (Route.updateOverrides (\overrides -> { overrides | distance = Just 800 })))
                        [ AtWaypoint 0 ]
                        |> Expect.equal [ 800 ]
            , test "an empty track has no internal boundaries" <|
                \_ -> ProfileSplit.pointDistances (Just 1000) (Route.EditableTrack [] [] 0 0) [ AtRoutePosition ] |> Expect.equal []
            , test "category distances use the same sorting, uniqueness and endpoint rules" <|
                \_ -> ProfileSplit.internalDistances 2000 [ 2000, 1500, 0, 500, 500, -1, 3000 ] |> Expect.equal [ 500, 1500 ]
            ]
        , describe "effective live window"
            (List.map
                (\( label, position, expected ) ->
                    test label <|
                        \_ -> ProfileSplit.liveRange { liveLookbehind = 100, liveLookahead = 200 } 2000 position |> Expect.equal expected
                )
                [ ( "no position displays the full track", Nothing, ( 0, 2000 ) )
                , ( "the route start clamps lookbehind", Just 0, ( 0, 200 ) )
                , ( "an interior position moves both ends", Just 1000, ( 900, 1200 ) )
                , ( "the route finish clamps lookahead", Just 2000, ( 1900, 2000 ) )
                ]
                ++ [ test "different positions can share a clamped window and reuse segments" <|
                        \_ ->
                            List.map (ProfileSplit.liveRange { liveLookbehind = 3000, liveLookahead = 3000 } 2000) [ Nothing, Just 0, Just 1000, Just 2000 ]
                                |> Expect.equal [ ( 0, 2000 ), ( 0, 2000 ), ( 0, 2000 ), ( 0, 2000 ) ]
                   , test "clearing an interior position restores the full track" <|
                        \_ ->
                            List.map (ProfileSplit.liveRange { liveLookbehind = 100, liveLookahead = 200 } 2000) [ Just 1000, Nothing ]
                                |> Expect.equal [ ( 900, 1200 ), ( 0, 2000 ) ]
                   ]
            )
        ]
