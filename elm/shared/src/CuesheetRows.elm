module CuesheetRows exposing (Info(..), waypointInfos)

{-| Prepare presentation rows while retaining the identity of synthetic points.
A position at the same distance as a waypoint is still a separate row and
breaks a group. Ride distances use the representatives' unrounded values.
-}

import GpxApi exposing (Waypoint)
import List.Extra
import Route exposing (PointRef(..))
import WaypointGrouping exposing (WaypointGroup)


type Info
    = InfoWaypoint Waypoint
    | InfoPosition Waypoint
    | InfoGroup WaypointGroup
    | InfoMember Int Waypoint
    | Ride Float ( Float, Float )


type Location
    = Group WaypointGroup
    | Synthetic PointRef Waypoint


waypointInfos : (Waypoint -> Maybe String) -> List ( PointRef, Waypoint ) -> List Info
waypointInfos displayLabel entries =
    let
        locations =
            groupLocations displayLabel entries
    in
    List.Extra.interweave
        (List.map locationRows locations)
        (List.map2
            (\previous current ->
                [ Ride ((representative current).distance - (representative previous).distance)
                    ( (representative current).gain - (representative previous).gain
                    , (representative current).loss - (representative previous).loss
                    )
                ]
            )
            locations
            (List.drop 1 locations)
        )
        |> List.concat


groupLocations : (Waypoint -> Maybe String) -> List ( PointRef, Waypoint ) -> List Location
groupLocations displayLabel entries =
    case entries of
        [] ->
            []

        ( AtWaypoint _, _ ) :: _ ->
            let
                ( members, remaining ) =
                    takeWaypoints [] entries
            in
            List.map Group (WaypointGrouping.groupWaypoints displayLabel members)
                ++ groupLocations displayLabel remaining

        ( ref, waypoint ) :: rest ->
            Synthetic ref waypoint :: groupLocations displayLabel rest


takeWaypoints : List ( Int, Waypoint ) -> List ( PointRef, Waypoint ) -> ( List ( Int, Waypoint ), List ( PointRef, Waypoint ) )
takeWaypoints reversed entries =
    case entries of
        ( AtWaypoint index, waypoint ) :: rest ->
            takeWaypoints (( index, waypoint ) :: reversed) rest

        _ ->
            ( List.reverse reversed, entries )


representative : Location -> Waypoint
representative location =
    case location of
        Group group ->
            Waypoint group.distance (WaypointGrouping.label group) [] group.gain group.loss 0

        Synthetic _ waypoint ->
            waypoint


locationRows : Location -> List Info
locationRows location =
    case location of
        Group group ->
            case group.members of
                [ ( _, waypoint ) ] ->
                    [ InfoWaypoint waypoint ]

                members ->
                    InfoGroup group :: List.map (\( index, waypoint ) -> InfoMember index waypoint) members

        Synthetic AtRoutePosition waypoint ->
            [ InfoPosition waypoint ]

        Synthetic _ waypoint ->
            [ InfoWaypoint waypoint ]
