port module Main exposing (storeState)

import Browser
import Browser.Navigation
import Dict
import Dropdown
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
    , options : Options
    }


type alias Options =
    { types : Dict.Dict String Bool
    , totalDistanceDisplay : TotalDistanceDisplay
    }


type TotalDistanceDisplay
    = FromFirst
    | FromLast
    | None


type alias Waypoint =
    { name : String
    , distance : Float
    , typ : String
    }


type alias DisplayWaypoint =
    { name : String
    , distance : Maybe Float
    , typ : String
    }


type alias RouteInfo =
    List Info


type Info
    = InfoWaypoint DisplayWaypoint
    | Ride Float


init : Maybe StoredState -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState |> Maybe.map (\state -> Model state.waypoints <| initialOptions state.waypoints) |> Maybe.withDefault (Model [] (Options Dict.empty FromFirst)), Cmd.none )


type Msg
    = Never
    | UpdateWaypoints (List Waypoint)
    | TypeEnabled String Bool
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)


initialOptions : List Waypoint -> Options
initialOptions waypoints =
    Options (initialTypes waypoints) FromFirst


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
                    Model sortedWaypoint (initialOptions sortedWaypoint)
            in
            ( newModel, storeModel newModel )

        TypeEnabled typ enabled ->
            let
                options =
                    model.options
            in
            ( { model | options = { options | types = Dict.insert typ enabled model.options.types } }, Cmd.none )

        UpdateTotalDistanceDisplay maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\selection ->
                        let
                            options =
                                model.options
                        in
                        ( { model | options = { options | totalDistanceDisplay = selection } }, Cmd.none )
                    )
                |> Maybe.withDefault ( model, Cmd.none )

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
        , Html.div [ Html.Attributes.class "row" ]
            [ waypointsAndOptions model
            , routeBreakdown (routeInfo model)
            ]
        ]


waypointsAndOptions : Model -> Html Msg
waypointsAndOptions model =
    Html.div [ Html.Attributes.class "column" ]
        [ Html.h2 [] [ Html.text "Waypoints" ]
        , div [] (List.map (\waypoint -> div [] [ Html.text ((++) (formatFloat waypoint.distance ++ " ") waypoint.name) ]) model.waypoints)
        , Html.br [] []
        , div []
            [ Html.h2 [] [ Html.text "Options" ]
            , Html.fieldset []
                (Html.legend [] [ Html.text "Location types:" ]
                    :: (model.options.types |> Dict.toList |> List.map (\( typ, included ) -> checkbox included (TypeEnabled typ (not included)) typ))
                )
            ]
        , div []
            (Html.legend [] [ Html.text "Total distance:" ]
                :: [ Dropdown.dropdown
                        (Dropdown.Options
                            [ Dropdown.Item "from first" "from first" True
                            , Dropdown.Item "from last" "from last" True
                            , Dropdown.Item "none" "none" True
                            ]
                            Maybe.Nothing
                            (\maybeSelection ->
                                maybeSelection
                                    |> Maybe.map
                                        (\selection ->
                                            case selection of
                                                "from first" ->
                                                    UpdateTotalDistanceDisplay (Maybe.Just FromFirst)

                                                "from last" ->
                                                    UpdateTotalDistanceDisplay (Maybe.Just FromLast)

                                                "none" ->
                                                    UpdateTotalDistanceDisplay (Maybe.Just None)

                                                _ ->
                                                    UpdateTotalDistanceDisplay Maybe.Nothing
                                        )
                                    |> Maybe.withDefault (UpdateTotalDistanceDisplay Maybe.Nothing)
                            )
                        )
                        []
                        (Maybe.Just "hello")
                   ]
            )
        ]


routeInfo : Model -> RouteInfo
routeInfo model =
    List.foldl
        (\el accum ->
            ( Maybe.Just el
            , ([ InfoWaypoint <|
                    DisplayWaypoint el.name
                        (case model.options.totalDistanceDisplay of
                            FromFirst ->
                                Maybe.Just el.distance

                            FromLast ->
                                List.head (List.reverse model.waypoints) |> Maybe.map (\last -> last.distance - el.distance)

                            None ->
                                Maybe.Nothing
                        )
                        el.typ
               ]
                ++ (Tuple.first accum
                        |> Maybe.map (\previous -> [ Ride (el.distance - previous.distance) ])
                        |> Maybe.withDefault []
                   )
              )
                ++ Tuple.second accum
            )
        )
        ( Maybe.Nothing, [] )
        (List.filter (\w -> Dict.get w.typ model.options.types |> Maybe.withDefault True) model.waypoints)
        |> Tuple.second
        |> List.reverse


routeBreakdown : RouteInfo -> Html Msg
routeBreakdown info =
    let
        svgHeight =
            String.fromInt <| (*) 20 (List.length info)
    in
    Html.div [ Html.Attributes.class "column" ]
        [ Html.h2 [] [ Html.text "Route breakdown" ]
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
                                        [ Svg.text <|
                                            waypoint.name
                                                ++ (waypoint.distance
                                                        |> Maybe.map
                                                            (\distance ->
                                                                " ("
                                                                    ++ formatFloat distance
                                                                    ++ "km)"
                                                            )
                                                        |> Maybe.withDefault ""
                                                   )
                                        ]
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
        , Html.label [ Html.Events.onClick msg ] [ Html.text name ]
        ]



-- STATE


storeModel : Model -> Cmd msg
storeModel model =
    Json.Encode.object
        [ ( "waypoints", encodeWaypoints model.waypoints )
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
