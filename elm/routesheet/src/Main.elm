port module Main exposing (storeState)

import Browser
import Browser.Navigation
import Dict
import Html exposing (Attribute, Html, div)
import Html.Attributes
import Html.Events
import Json.Encode
import String
import Svg
import Svg.Attributes
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


type alias StoredState =
    { waypoints : List Waypoint }


type alias Model =
    { waypoints : List Waypoint

    -- maintained as list to allow easy interoperability with state storage and initialisation of flags.
    -- flags can't handle being a set
    , types : Dict.Dict String Bool
    }


type alias Waypoint =
    { name : String
    , distance : Float
    , typ : String
    }


type alias RouteInfo =
    List Info


type Info
    = InfoWaypoint Waypoint
    | Ride Float


init : Maybe StoredState -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState |> Maybe.map (\state -> Model state.waypoints <| initialTypes state.waypoints) |> Maybe.withDefault (Model [] Dict.empty), Cmd.none )


type Msg
    = Never
    | UpdateWaypoints (List Waypoint)
    | TypeEnabled String Bool


initialTypes : List Waypoint -> Dict.Dict String Bool
initialTypes waypoints =
    List.map (\el -> ( el.typ, True )) waypoints |> Dict.fromList


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateWaypoints waypoints ->
            let
                sortedWaypoint =
                    List.sortBy .distance waypoints

                newModel =
                    Model sortedWaypoint (initialTypes sortedWaypoint)
            in
            ( newModel, storeModel newModel )

        TypeEnabled typ enabled ->
            ( { model | types = Dict.insert typ enabled model.types }, Cmd.none )

        Never ->
            ( model, Cmd.none )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    let
        info =
            routeInfo model

        svgHeight =
            String.fromInt <| (*) 20 (List.length info)
    in
    Browser.Document "Route sheet"
        [ div []
            [ Html.button
                [ Html.Events.onClick <|
                    UpdateWaypoints
                        [ Waypoint "start" 0 "Landmark"
                        , Waypoint "foo" 1.234567 "Resupply"
                        , Waypoint "bar" 2.345678 "Sleep"
                        , Waypoint "baz" 3.456789 "Resupply"
                        , Waypoint "anywhere" 32.9 "Municipality"
                        , Waypoint "qux" 4.567891 "Sleep"
                        , Waypoint "finish" 99.567891 "Landmark"
                        ]
                ]
                [ Html.text "hello" ]
            ]
        , Html.h2 [] [ Html.text "Waypoints" ]
        , div [] (List.map (\waypoint -> div [] [ Html.text ((++) (formatFloat waypoint.distance ++ " ") waypoint.name) ]) model.waypoints)
        , Html.br [] []
        , div []
            [ Html.h2 [] [ Html.text "Options" ]
            , Html.fieldset []
                (Html.legend [] [ Html.text "Location types" ]
                    :: (model.types |> Dict.toList |> List.map (\( typ, included ) -> checkbox included (TypeEnabled typ (not included)) typ))
                )
            ]
        , Html.h2 [] [ Html.text "Route breakdown" ]
        , Svg.svg
            [ Svg.Attributes.width "120"
            , Svg.Attributes.height svgHeight
            , Svg.Attributes.viewBox <| "0 0 120 " ++ svgHeight
            ]
            (info
                |> List.indexedMap
                    (\i item ->
                        let
                            translate =
                                Svg.Attributes.transform <| "translate(0," ++ (String.fromInt <| i * 20) ++ ")"
                        in
                        case item of
                            InfoWaypoint waypoint ->
                                Svg.g [ translate ]
                                    [ Svg.circle
                                        [ Svg.Attributes.cx "5"
                                        , Svg.Attributes.cy <| String.fromInt 10
                                        , Svg.Attributes.r "2"
                                        ]
                                        []
                                    , Svg.text_
                                        [ Svg.Attributes.x "10"
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.y <| String.fromInt 10
                                        ]
                                        [ Svg.text <| waypoint.name ++ " (" ++ formatFloat waypoint.distance ++ "km)" ]
                                    ]

                            Ride dist ->
                                Svg.g [ translate ]
                                    [ Svg.line
                                        [ Svg.Attributes.x1 "5"
                                        , Svg.Attributes.y1 <| String.fromInt 0
                                        , Svg.Attributes.x2 "5"
                                        , Svg.Attributes.y2 <| String.fromInt 20
                                        , Svg.Attributes.stroke "black"
                                        , Svg.Attributes.strokeWidth "0.5"
                                        ]
                                        []
                                    , Svg.text_
                                        [ Svg.Attributes.x "10"
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.y <| String.fromInt 10
                                        ]
                                        [ Svg.text <| formatFloat dist ]
                                    ]
                    )
            )
        ]


routeInfo : Model -> RouteInfo
routeInfo model =
    List.foldl
        (\el accum ->
            ( Maybe.Just el
            , ([ InfoWaypoint el ]
                ++ (Tuple.first accum
                        |> Maybe.map (\previous -> [ Ride (el.distance - previous.distance) ])
                        |> Maybe.withDefault []
                   )
              )
                ++ Tuple.second accum
            )
        )
        ( Maybe.Nothing, [] )
        (List.filter (\w -> Dict.get w.typ model.types |> Maybe.withDefault True) model.waypoints)
        |> Tuple.second
        |> List.reverse


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


checkbox : Bool -> msg -> String -> Html msg
checkbox b msg name =
    Html.div []
        [ Html.input [ Html.Attributes.type_ "checkbox", Html.Events.onClick msg, Html.Attributes.checked b ] []
        , Html.label [] [ Html.text name ]
        ]



-- STATE


storeModel : Model -> Cmd msg
storeModel model =
    Json.Encode.object
        [ ( "waypoints", encodeWaypoints model.waypoints )
        , ( "types", Json.Encode.dict (\key -> key) Json.Encode.bool model.types )
        ]
        |> Json.Encode.encode 2
        |> storeState


encodeWaypoints : List Waypoint -> Json.Encode.Value
encodeWaypoints waypoints =
    Json.Encode.list
        (\waypoint ->
            Json.Encode.object
                [ ( "name", Json.Encode.string waypoint.name )
                , ( "distance", Json.Encode.float waypoint.distance )
                , ( "typ", Json.Encode.string waypoint.typ )
                ]
        )
        waypoints


port storeState : String -> Cmd msg
