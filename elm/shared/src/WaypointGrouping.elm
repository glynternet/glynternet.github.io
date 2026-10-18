module WaypointGrouping exposing (WaypointGroup, groupWaypoints, label)

{-| Presentation groups retain the original indices and unmodified waypoints.
The caller supplies display labels and route order; this module knows nothing
about units, rounding, filters, app state or rendering.
-}

import GpxApi exposing (Waypoint)
import List.Extra


type alias WaypointGroup =
    { members : List ( Int, Waypoint )
    , distance : Float
    , gain : Float
    , loss : Float
    }


groupWaypoints : (Waypoint -> Maybe String) -> List ( Int, Waypoint ) -> List WaypointGroup
groupWaypoints displayLabel waypoints =
    waypoints
        |> List.foldl
            (\(( _, waypoint ) as member) ( previousLabel, groups ) ->
                let
                    currentLabel =
                        displayLabel waypoint
                in
                case groups of
                    group :: rest ->
                        if currentLabel /= Nothing && currentLabel == previousLabel then
                            ( currentLabel, { group | members = member :: group.members } :: rest )

                        else
                            ( currentLabel, singleton member :: groups )

                    [] ->
                        ( currentLabel, [ singleton member ] )
            )
            ( Nothing, [] )
        |> Tuple.second
        |> List.reverse
        |> List.map (\group -> { group | members = List.reverse group.members })


singleton : ( Int, Waypoint ) -> WaypointGroup
singleton (( _, waypoint ) as member) =
    { members = [ member ]
    , distance = waypoint.distance
    , gain = waypoint.gain
    , loss = waypoint.loss
    }


{-| Group headings use distinct nonblank names; every individual name remains
available on the member rows, including duplicates and unnamed members.
-}
label : WaypointGroup -> String
label group =
    case group.members |> List.map (Tuple.second >> .name >> String.trim) |> List.filter ((/=) "") |> List.Extra.unique of
        [] ->
            String.fromInt (List.length group.members) ++ " waypoints"

        names ->
            String.join " · " names
