module Main exposing (..)

import Browser
import Browser.Navigation
import Html exposing (Attribute, Html, div)
import Html.Events
import String
import Url exposing (Protocol(..))



-- MAIN


main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = \_ -> Never
        , onUrlChange = \_ -> Never
        }



-- MODEL


type alias Model =
    { waypoints : List Waypoint
    , routeSheet : RouteSheet
    }


type alias Waypoint =
    { name : String
    , distance : Float
    , typ : String
    }


type alias RouteSheet =
    { info : List Info
    }


type Info
    = InfoWaypoint Waypoint
    | Ride Float


init : () -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ _ _ =
    ( Model [] <| RouteSheet [], Cmd.none )


type Msg
    = Never
    | UpdateWaypoints (List Waypoint)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateWaypoints waypoints ->
            ( Model waypoints (RouteSheet (List.foldl (\el accum -> ( el, [ InfoWaypoint el, Ride (el.distance - (Tuple.first accum).distance) ] ++ Tuple.second accum )) ( Waypoint "start" 0.0 "Landmark", [ InfoWaypoint <| Waypoint "start" 0.0 "Landmark" ] ) waypoints |> Tuple.second |> List.reverse))
            , Cmd.none
            )

        Never ->
            ( model, Cmd.none )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    Browser.Document "Route sheet"
        [ div []
            [ Html.button
                [ Html.Events.onClick <|
                    UpdateWaypoints
                        [ Waypoint "foo" 1.234567 "Resupply"
                        , Waypoint "bar" 2.345678 "Sleep"
                        , Waypoint "baz" 3.456789 "Resupply"
                        , Waypoint "qux" 4.567891 "Sleep"
                        ]
                ]
                [ Html.text "hello" ]
            ]
        , Html.h2 [] [ Html.text "Waypoints" ]
        , div [] (List.map (\waypoint -> div [] [ Html.text ((++) (formatFloat waypoint.distance ++ " ") waypoint.name) ]) model.waypoints)
        , Html.br [] []
        , Html.h2 [] [ Html.text "Route breakdown" ]
        , div []
            (List.map
                (\infoPoint ->
                    div []
                        [ Html.text
                            (case infoPoint of
                                Ride dist ->
                                    String.join " " [ "|", "ride", formatFloat dist ]

                                InfoWaypoint waypoint ->
                                    String.join " " [ formatFloat waypoint.distance, waypoint.typ, waypoint.name ]
                            )
                        ]
                )
                model.routeSheet.info
            )
        ]


formatFloat : Float -> String
formatFloat value =
    case String.split "." (String.fromFloat value) of
        [ val ] ->
            val ++ ".00"

        [ val, dec ] ->
            String.join "."
                [ val
                , String.left 2 dec |> String.padRight 2 '0'
                ]

        _ ->
            "please contact Glyn"
