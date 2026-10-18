module CuesheetRowsTest exposing (suite)

import CuesheetRows exposing (Info(..))
import DistanceDisplay
import Expect
import GpxApi exposing (Waypoint)
import Route exposing (PointRef(..))
import Test exposing (Test, describe, test)
import WaypointGrouping


first : Waypoint
first =
    Waypoint 300 "Water" [ "water" ] 10 2 0


second : Waypoint
second =
    Waypoint 304 "Camp" [ "camp" ] 14 3 30


suite : Test
suite =
    describe "Cuesheet row preparation"
        [ test "expanded members preserve indices and values; rides use unrounded representatives" <|
            \_ ->
                let
                    members =
                        [ ( 8, first ), ( 3, second ) ]

                    finish =
                        Waypoint 1000 "Finish" [] 60 4 0
                in
                CuesheetRows.waypointInfos (DistanceDisplay.fromStartLabel 2)
                    [ ( AtWaypoint 8, first ), ( AtWaypoint 3, second ), ( AtRouteEnd, finish ) ]
                    |> Expect.equal
                        (List.map InfoGroup (WaypointGrouping.groupWaypoints (DistanceDisplay.fromStartLabel 2) members)
                            ++ [ InfoMember 8 first, InfoMember 3 second, Ride 700 ( 50, 2 ), InfoWaypoint finish ]
                        )
        , test "a coincident position stays a position and the actual waypoint stays a waypoint" <|
            \_ ->
                CuesheetRows.waypointInfos (always (Just "same"))
                    [ ( AtWaypoint 8, first ), ( AtRoutePosition, first ), ( AtWaypoint 3, second ) ]
                    |> Expect.equal [ InfoWaypoint first, Ride 0 ( 0, 0 ), InfoPosition first, Ride 4 ( 4, 1 ), InfoWaypoint second ]
        , test "synthetic endpoints remain separate even with matching labels" <|
            \_ ->
                CuesheetRows.waypointInfos (always (Just "same"))
                    [ ( AtRouteStart, first ), ( AtWaypoint 8, first ), ( AtRouteEnd, second ) ]
                    |> Expect.equal [ InfoWaypoint first, Ride 0 ( 0, 0 ), InfoWaypoint first, Ride 4 ( 4, 1 ), InfoWaypoint second ]
        , test "an empty cuesheet has no rows" <|
            \_ -> CuesheetRows.waypointInfos (always Nothing) [] |> Expect.equal []
        ]
