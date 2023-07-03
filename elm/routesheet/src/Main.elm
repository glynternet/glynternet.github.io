port module Main exposing (storeState)

import Browser
import Browser.Navigation
import Csv.Decode
import Dict
import Dropdown
import File
import File.Select
import Html exposing (Attribute, Html, div)
import Html.Attributes
import Html.Events
import Json.Decode
import Json.Encode
import String
import Svg
import Svg.Attributes
import Task
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
    { waypoints : List Waypoint
    , totalDistanceDisplay : String
    , types : Json.Decode.Value
    }


type alias Model =
    { waypoints : List Waypoint
    , options : Options
    }


type alias Options =
    { locationFilterEnabled : Bool
    , types : Dict.Dict String Bool
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
    , typ : Maybe String
    }


type alias RouteInfo =
    List Info


type Info
    = InfoWaypoint DisplayWaypoint
    | Ride Float


init : Maybe StoredState -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState
        |> Maybe.map
            (\state ->
                Model state.waypoints <|
                    Options
                        False
                        (Json.Decode.decodeValue (Json.Decode.dict Json.Decode.bool) state.types
                            --TODO: handle error
                            |> Result.withDefault (initialTypes state.waypoints)
                        )
                        (parseTotalDistanceDisplay state.totalDistanceDisplay |> Maybe.withDefault FromFirst)
            )
        |> Maybe.withDefault (Model [] (Options False Dict.empty FromFirst))
    , Cmd.none
    )


type Msg
    = Never
    | TypeEnabled String Bool
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdateWaypointSelection (Maybe Bool)
    | OpenFileBrowser
    | FileUploaded File.File
    | CsvDecoded (Result Csv.Decode.Error (List Waypoint))


initialOptions : List Waypoint -> Options
initialOptions waypoints =
    Options False (initialTypes waypoints) FromFirst


initialTypes : List Waypoint -> Dict.Dict String Bool
initialTypes waypoints =
    List.map (\el -> ( el.typ, True )) waypoints |> Dict.fromList


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        TypeEnabled typ enabled ->
            let
                options =
                    model.options

                newModel =
                    { model | options = { options | types = Dict.insert typ enabled model.options.types } }
            in
            updateModel newModel

        UpdateTotalDistanceDisplay maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\selection ->
                        let
                            options =
                                model.options
                        in
                        updateModel { model | options = { options | totalDistanceDisplay = selection } }
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdateWaypointSelection maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\locationFilterEnabled ->
                        let
                            options =
                                model.options
                        in
                        updateModel { model | options = { options | locationFilterEnabled = locationFilterEnabled } }
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        OpenFileBrowser ->
            ( model, File.Select.file [ "text/csv" ] FileUploaded )

        FileUploaded file ->
            ( model
            , File.toString file
                |> Task.map
                    (\content ->
                        Csv.Decode.decodeCsv Csv.Decode.FieldNamesFromFirstRow
                            (Csv.Decode.into Waypoint
                                |> Csv.Decode.pipeline (Csv.Decode.field "Name" Csv.Decode.string)
                                |> Csv.Decode.pipeline (Csv.Decode.field "Distance" Csv.Decode.float)
                                |> Csv.Decode.pipeline (Csv.Decode.field "Type" Csv.Decode.string)
                            )
                            content
                    )
                |> Task.perform CsvDecoded
            )

        CsvDecoded result ->
            result
                |> Result.map (initialModel >> updateModel)
                |> Result.withDefault ( model, Cmd.none )

        Never ->
            ( model, Cmd.none )


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    ( model, storeModel model )


initialModel : List Waypoint -> Model
initialModel waypoints =
    let
        sortedWaypoint =
            List.sortBy .distance waypoints
    in
    Model sortedWaypoint (initialOptions sortedWaypoint)



-- VIEW


view : Model -> Browser.Document Msg
view model =
    Browser.Document "Route sheet"
        [ div []
            [ Html.button
                [ Html.Events.onClick OpenFileBrowser ]
                [ Html.text "upload csv" ]
            ]
        , Html.div [ Html.Attributes.class "row" ]
            [ waypointsAndOptions model
            , routeBreakdown (routeInfo model)
            ]
        ]


waypointsAndOptions : Model -> Html Msg
waypointsAndOptions model =
    Html.div [ Html.Attributes.class "column", Html.Attributes.class "narrow" ]
        [ div [] <|
            List.concat
                [ [ Html.h2 [] [ Html.text "Options" ]
                  , Html.legend [] [ Html.text "Waypoint selection" ]
                  , Dropdown.dropdown
                        (Dropdown.Options
                            [ Dropdown.Item "all" "all" True
                            , Dropdown.Item "filtered" "filtered" True
                            ]
                            Maybe.Nothing
                            (Maybe.map
                                (\selection ->
                                    case selection of
                                        "all" ->
                                            Maybe.Just False

                                        "filtered" ->
                                            Maybe.Just True

                                        _ ->
                                            Maybe.Nothing
                                )
                                >> Maybe.withDefault Maybe.Nothing
                                >> UpdateWaypointSelection
                            )
                        )
                        []
                        (Maybe.Just <| formatTotalDistanceDisplay model.options.totalDistanceDisplay)
                  ]
                , if model.options.locationFilterEnabled then
                    [ Html.fieldset []
                        (Html.legend [] [ Html.text "Location types:" ]
                            :: (model.options.types
                                    |> Dict.toList
                                    |> List.map
                                        (\( typ, included ) ->
                                            checkbox included
                                                (TypeEnabled typ (not included))
                                                (if typ /= "" then
                                                    typ

                                                 else
                                                    "none"
                                                )
                                        )
                               )
                        )
                    ]

                  else
                    []
                , [ div []
                        [ Html.legend [] [ Html.text "Total distance:" ]
                        , Dropdown.dropdown
                            (Dropdown.Options
                                [ Dropdown.Item (formatTotalDistanceDisplay FromFirst) (formatTotalDistanceDisplay FromFirst) True
                                , Dropdown.Item (formatTotalDistanceDisplay FromLast) (formatTotalDistanceDisplay FromLast) True
                                , Dropdown.Item (formatTotalDistanceDisplay None) (formatTotalDistanceDisplay None) True
                                ]
                                Maybe.Nothing
                                (Maybe.map parseTotalDistanceDisplay
                                    >> Maybe.withDefault Maybe.Nothing
                                    >> UpdateTotalDistanceDisplay
                                )
                            )
                            []
                            (Maybe.Just <| formatTotalDistanceDisplay model.options.totalDistanceDisplay)
                        ]
                  ]
                ]
        , Html.br [] []
        , Html.h2 [] [ Html.text "Waypoints" ]
        , div [] (List.map (\waypoint -> div [] [ Html.text ((++) (formatFloat waypoint.distance ++ " ") waypoint.name) ]) model.waypoints)
        ]


parseTotalDistanceDisplay : String -> Maybe TotalDistanceDisplay
parseTotalDistanceDisplay v =
    case v of
        "from first" ->
            Maybe.Just FromFirst

        "from last" ->
            Maybe.Just FromLast

        "none" ->
            Maybe.Just None

        _ ->
            Maybe.Nothing


formatTotalDistanceDisplay : TotalDistanceDisplay -> String
formatTotalDistanceDisplay v =
    case v of
        FromFirst ->
            "from first"

        FromLast ->
            "from last"

        None ->
            "none"


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
                        (if el.typ /= "" then
                            Maybe.Just el.typ

                         else
                            Maybe.Nothing
                        )
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
        (if model.options.locationFilterEnabled then
            List.filter (\w -> Dict.get w.typ model.options.types |> Maybe.withDefault True) model.waypoints

         else
            model.waypoints
        )
        |> Tuple.second
        |> List.reverse


routeBreakdown : RouteInfo -> Html Msg
routeBreakdown info =
    let
        svgHeight =
            String.fromInt <| (*) 20 (List.length info)

        svgContentLeftStart =
            0

        svgContentLeftStartString =
            String.fromInt svgContentLeftStart
    in
    Html.div [ Html.Attributes.class "column", Html.Attributes.class "wide" ]
        [ Html.h2 [ Html.Attributes.style "text-align" "center" ] [ Html.text "Route breakdown" ]
        , Svg.svg
            [ Svg.Attributes.class "route_breakdown"
            , Svg.Attributes.width "100%"
            , Svg.Attributes.height svgHeight
            , Svg.Attributes.viewBox <| "-120 0 240 " ++ svgHeight
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
                                let
                                    waypointInfo =
                                        List.filterMap identity
                                            [ Maybe.map (\dist -> formatFloat dist ++ "km") waypoint.distance, waypoint.typ ]

                                    waypointInfoLines =
                                        if List.isEmpty waypointInfo then
                                            [ "◉" ]

                                        else
                                            waypointInfo
                                in
                                Svg.g [ translate ]
                                    (Svg.text_
                                        [ Svg.Attributes.x (String.fromInt <| svgContentLeftStart + 10)
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.y <| String.fromInt 10
                                        ]
                                        [ Svg.text waypoint.name ]
                                        :: (waypointInfoLines
                                                |> List.indexedMap
                                                    (\j line ->
                                                        Svg.text_
                                                            [ Svg.Attributes.x svgContentLeftStartString
                                                            , Svg.Attributes.y <| String.fromInt 10
                                                            , Svg.Attributes.dominantBaseline "middle"
                                                            , Svg.Attributes.dy (String.fromFloat 2 ++ "em")
                                                            , Svg.Attributes.dy (String.fromFloat (toFloat j - (toFloat <| List.length waypointInfoLines - 1) / 2) ++ "em")
                                                            , Svg.Attributes.textAnchor "end"
                                                            , Svg.Attributes.fontSize "smaller"
                                                            ]
                                                            [ Svg.text line ]
                                                    )
                                           )
                                    )

                            Ride dist ->
                                let
                                    barTop =
                                        "2"

                                    barBottom =
                                        "18"
                                in
                                Svg.g [ translate ]
                                    [ Svg.line
                                        [ Svg.Attributes.x1 svgContentLeftStartString
                                        , Svg.Attributes.y1 barTop
                                        , Svg.Attributes.x2 svgContentLeftStartString
                                        , Svg.Attributes.y2 barBottom
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth "0.5"
                                        ]
                                        []
                                    , Svg.line
                                        [ Svg.Attributes.x1 <| String.fromInt <| svgContentLeftStart - 2
                                        , Svg.Attributes.y1 barTop
                                        , Svg.Attributes.x2 <| String.fromInt <| svgContentLeftStart + 2
                                        , Svg.Attributes.y2 barTop
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth "0.5"
                                        ]
                                        []
                                    , Svg.line
                                        [ Svg.Attributes.x1 <| String.fromInt <| svgContentLeftStart - 2
                                        , Svg.Attributes.y1 barBottom
                                        , Svg.Attributes.x2 <| String.fromInt <| svgContentLeftStart + 2
                                        , Svg.Attributes.y2 barBottom
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth "0.5"
                                        ]
                                        []
                                    , Svg.text_
                                        [ Svg.Attributes.x (String.fromInt <| svgContentLeftStart + 10)
                                        , Svg.Attributes.y <| String.fromInt 10
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.fontSize "smaller"
                                        ]
                                        [ Svg.text <| formatFloat dist ++ "km" ]
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
-- The field names in these encoded JSON objects must match exactly the field names
-- in the records of the Model to ensure that deserialising works as expected.


storeModel : Model -> Cmd msg
storeModel model =
    Json.Encode.object
        [ ( "waypoints", encodeWaypoints model.waypoints )
        , ( "totalDistanceDisplay", Json.Encode.string <| formatTotalDistanceDisplay model.options.totalDistanceDisplay )
        , ( "types", Json.Encode.dict identity Json.Encode.bool model.options.types )
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
