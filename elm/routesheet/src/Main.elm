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


type alias Waypoint =
    { name : String
    , distance : Float
    }


type alias Model =
    { waypoints : List Waypoint
    }


init : () -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ _ _ =
    -- this is actually not required to update the waypoints, just playing around.
    ( Model [], Cmd.none )


type Msg
    = Never
    | UpdateWaypoints (List Waypoint)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateWaypoints waypoints ->
            ( Model waypoints, Cmd.none )

        Never ->
            ( model, Cmd.none )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    Browser.Document "Next Actions"
        [ div []
            [ Html.button
                [ Html.Events.onClick <|
                    UpdateWaypoints [ Waypoint "foo" 1.234567, Waypoint "bar" 2.345678, Waypoint "baz" 3.456789 ]
                ]
                [ Html.text "hello" ]
            ]
        , div [] (List.map (\waypoint -> div [] [ Html.text ((++) (String.fromFloat waypoint.distance ++ " ") waypoint.name) ]) model.waypoints)
        ]
