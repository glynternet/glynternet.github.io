port module Main exposing (storeState)

import Browser
import Browser.Navigation
import Csv.Decode
import Dict
import Dropdown
import File
import File.Download
import File.Select
import Html exposing (Attribute, Html)
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
    { waypoints : Maybe (List Waypoint)
    , totalDistanceDisplay : String
    , locationFilterEnabled : Bool
    , filteredLocationTypes : Json.Decode.Value
    , itemSpacing : Int
    }


type alias Model =
    { waypoints : Maybe (List Waypoint)
    , waypointOptions : WaypointsOptions
    , routeViewOptions : RouteViewOptions
    }


type alias WaypointsOptions =
    { locationFilterEnabled : Bool
    , filteredLocationTypes : Dict.Dict String Bool
    }


type alias RouteViewOptions =
    { totalDistanceDisplay : TotalDistanceDisplay
    , itemSpacing : Int
    }


type TotalDistanceDisplay
    = FromZero
    | FromLast
    | None


type alias Waypoint =
    { name : String
    , distance : Float
    , typ : String
    }


type Info
    = InfoWaypoint Waypoint
    | Ride Float


init : Maybe StoredState -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState
        |> Maybe.map
            (\state ->
                Model state.waypoints
                    (WaypointsOptions
                        state.locationFilterEnabled
                        (Json.Decode.decodeValue (Json.Decode.dict Json.Decode.bool) state.filteredLocationTypes
                            --TODO: handle error
                            |> Result.withDefault (initialFilteredLocations (Maybe.withDefault [] state.waypoints))
                        )
                    )
                    (RouteViewOptions (parseTotalDistanceDisplay state.totalDistanceDisplay |> Maybe.withDefault FromZero)
                        state.itemSpacing
                    )
            )
        |> Maybe.withDefault (Model Maybe.Nothing (WaypointsOptions False Dict.empty) (RouteViewOptions FromZero defaultSpacing))
    , Cmd.none
    )


type Msg
    = Never
    | TypeEnabled String Bool
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdateWaypointSelection (Maybe Bool)
    | UpdateItemSpacing Int
    | OpenFileBrowser
    | FileUploaded File.File
    | CsvDecoded (Result Csv.Decode.Error (List Waypoint))
    | LoadDemoData
    | DownloadDemoData
    | ClearWaypoints


initialWaypointOptions : List Waypoint -> WaypointsOptions
initialWaypointOptions waypoints =
    WaypointsOptions False (initialFilteredLocations waypoints)


initialFilteredLocations : List Waypoint -> Dict.Dict String Bool
initialFilteredLocations waypoints =
    List.map (\el -> ( el.typ, True )) waypoints |> Dict.fromList


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        TypeEnabled typ enabled ->
            let
                options =
                    model.waypointOptions

                newModel =
                    { model | waypointOptions = { options | filteredLocationTypes = Dict.insert typ enabled model.waypointOptions.filteredLocationTypes } }
            in
            updateModel newModel

        UpdateTotalDistanceDisplay maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\selection ->
                        let
                            options =
                                model.routeViewOptions
                        in
                        updateModel { model | routeViewOptions = { options | totalDistanceDisplay = selection } }
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdateWaypointSelection maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\locationFilterEnabled ->
                        let
                            options =
                                model.waypointOptions
                        in
                        updateModel { model | waypointOptions = { options | locationFilterEnabled = locationFilterEnabled } }
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdateItemSpacing spacing ->
            let
                options =
                    model.routeViewOptions
            in
            updateModel { model | routeViewOptions = { options | itemSpacing = spacing } }

        OpenFileBrowser ->
            ( model, File.Select.file [ "text/csv" ] FileUploaded )

        FileUploaded file ->
            ( model
            , File.toString file
                |> Task.map decodeCSV
                |> Task.perform CsvDecoded
            )

        CsvDecoded result ->
            result
                |> Result.map (initialModel model.routeViewOptions >> updateModel)
                --TODO: handle decode error
                |> Result.withDefault ( model, Cmd.none )

        LoadDemoData ->
            decodeCSV demoData
                |> Result.map (initialModel model.routeViewOptions >> updateModel)
                --TODO: handle decode error
                |> Result.withDefault ( model, Cmd.none )

        DownloadDemoData ->
            ( model, File.Download.string "demo-data.csv" "text/csv" demoData )

        ClearWaypoints ->
            updateModel { model | waypoints = Maybe.Nothing }

        Never ->
            ( model, Cmd.none )


decodeCSV : String -> Result Csv.Decode.Error (List Waypoint)
decodeCSV =
    Csv.Decode.decodeCsv Csv.Decode.FieldNamesFromFirstRow
        (Csv.Decode.into Waypoint
            |> Csv.Decode.pipeline (Csv.Decode.field "Name" Csv.Decode.string)
            |> Csv.Decode.pipeline (Csv.Decode.field "Distance" Csv.Decode.float)
            |> Csv.Decode.pipeline (Csv.Decode.field "Type" Csv.Decode.string)
        )


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    ( model, storeModel model )


initialModel : RouteViewOptions -> List Waypoint -> Model
initialModel routeViewOptions waypoints =
    let
        sortedWaypoint =
            List.sortBy .distance waypoints
    in
    Model (Maybe.Just sortedWaypoint) (initialWaypointOptions sortedWaypoint) routeViewOptions



-- VIEW


view : Model -> Browser.Document Msg
view model =
    Browser.Document "Route sheet"
        [ model.waypoints
            |> Maybe.map
                (\w ->
                    Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "row"
                        , Html.Attributes.class "page"
                        ]
                        [ viewOptions model.waypointOptions model.routeViewOptions
                        , Html.div [ Html.Attributes.class "column", Html.Attributes.class "wide" ]
                            [ Html.h2 [ Html.Attributes.style "text-align" "center" ] [ Html.text "Route breakdown" ]
                            , routeBreakdown (routeWaypoints model.waypointOptions w) model.routeViewOptions
                            ]
                        ]
                )
            |> Maybe.withDefault welcomePage
        ]


welcomePage : Html Msg
welcomePage =
    let
        climbType =
            "CLIMB"

        cafeType =
            "CAFE"

        exampleWaypoints =
            [ Waypoint "Start" 0.0 ""
            , Waypoint "Blue shoes" 56.1 cafeType
            , Waypoint "Lungburner" 56.3 climbType
            , Waypoint "Steep Street" 63.7 climbType
            , Waypoint "Foosville fountain" 98.3 "WATER"
            , Waypoint "Cosy hedge" 198.2 "😴"
            , Waypoint "Legburner" 243.8 climbType
            , Waypoint "Finish" 273.5 ""
            ]
    in
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "flex-center"
        , Html.Attributes.class "column"
        , Html.Attributes.class "examples"
        ]
        [ Html.p [] [ Html.text "hello and welcome" ]
        , Html.p [] [ Html.text "If you know what you're doing, click the upload button below." ]
        , viewUploadButton
        , Html.br [] []
        , Html.p [] [ Html.text "To play with some demo data, click the button below." ]
        , loadDemoDataButton
        , Html.br [] []
        , Html.p [] [ Html.text "To download demo data, click the button below." ]
        , downloadDemoDataButton
        , Html.br [] []
        , Html.p [] [ Html.text "Features" ]
        , Html.ul []
            [ Html.li [] [ Html.text "Customise information level" ]
            , Html.li [] [ Html.text "Compact or spacious view" ]
            , Html.li [] [ Html.text "User-defined location types" ]
            , Html.li [] [ Html.text "Filter location types" ]
            , Html.li [] [ Html.text "...and more." ]
            ]
        , Html.p [] [ Html.text "Examples:" ]
        , Html.div
            [ Html.Attributes.style "width" "100%"
            , Html.Attributes.style "justify-content" "space-evenly"
            , Html.Attributes.class "flex-container"
            , Html.Attributes.class "flex-center"
            , Html.Attributes.class "flex-wrap"
            , Html.Attributes.class "wide-row-narrow-column"
            ]
            (List.map (\( desc, waypointModifier, opts ) -> Html.div [] [ Html.h4 [ Html.Attributes.style "text-align" "center" ] [ Html.text desc ], routeBreakdown (waypointModifier exampleWaypoints) opts ])
                [ ( "Distance from zero", identity, RouteViewOptions FromZero defaultSpacing )
                , ( "Distance to go", identity, RouteViewOptions FromLast defaultSpacing )
                , ( "Custom location types"
                  , List.map
                        (\w ->
                            { w
                                | typ =
                                    Dict.get w.typ (Dict.fromList [ ( cafeType, "☕" ), ( climbType, "⛰️" ) ])
                                        |> Maybe.withDefault ""
                            }
                        )
                  , RouteViewOptions None defaultSpacing
                  )
                , ( "Custom spacing", identity, RouteViewOptions None (defaultSpacing - 10) )
                , ( "Filter location types", routeWaypoints (WaypointsOptions True (initialFilteredLocations exampleWaypoints |> Dict.map (\k _ -> k == climbType || k == ""))), RouteViewOptions None defaultSpacing )
                ]
            )
        ]


optionGroup : String -> List (Html Msg) -> Html Msg
optionGroup title elements =
    Html.div [ Html.Attributes.class "flex-container", Html.Attributes.class "column" ]
        (Html.legend [] [ Html.text title ] :: elements)


viewOptions : WaypointsOptions -> RouteViewOptions -> Html Msg
viewOptions waypointOptions routeViewOptions =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "justify-content" "center"
        , Html.Attributes.style "overflow" "auto"
        , Html.Attributes.class "narrow"
        ]
        [ Html.div [ Html.Attributes.class "options" ] <|
            [ Html.h2 [] [ Html.text "Options" ]
            , Html.hr [] []
            , optionGroup "Waypoint types"
                (Dropdown.dropdown
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
                    (Maybe.Just <|
                        if waypointOptions.locationFilterEnabled then
                            "filtered"

                        else
                            "all"
                    )
                    :: (if waypointOptions.locationFilterEnabled then
                            [ Html.fieldset []
                                (waypointOptions.filteredLocationTypes
                                    |> Dict.toList
                                    |> List.map
                                        (\( typ, included ) ->
                                            checkbox included
                                                (TypeEnabled typ (not included))
                                                (if typ /= "" then
                                                    typ

                                                 else
                                                    "unknown"
                                                )
                                        )
                                )
                            ]

                        else
                            []
                       )
                )
            , Html.hr [] []
            , optionGroup "Total distance"
                [ Dropdown.dropdown
                    (Dropdown.Options
                        [ Dropdown.Item (formatTotalDistanceDisplay FromZero) (formatTotalDistanceDisplay FromZero) True
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
                    (Maybe.Just <| formatTotalDistanceDisplay routeViewOptions.totalDistanceDisplay)
                ]
            , Html.hr [] []
            , optionGroup "Spacing"
                [ Html.input
                    [ Html.Attributes.type_ "range"
                    , Html.Attributes.min "1"
                    , Html.Attributes.max "50"
                    , Html.Attributes.value <| String.fromInt routeViewOptions.itemSpacing
                    , Html.Events.onInput (String.toInt >> Maybe.withDefault defaultSpacing >> UpdateItemSpacing)
                    ]
                    []
                ]
            , Html.hr [] []
            , viewUploadButton
            , Html.button
                [ Html.Events.onClick ClearWaypoints, Html.Attributes.class "button-4" ]
                [ Html.text "clear" ]
            ]
        ]


viewUploadButton : Html Msg
viewUploadButton =
    Html.button
        [ Html.Events.onClick OpenFileBrowser, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ]
        [ Html.text "upload waypoints" ]


loadDemoDataButton : Html Msg
loadDemoDataButton =
    Html.button
        [ Html.Events.onClick LoadDemoData, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ]
        [ Html.text "demo data plz" ]


downloadDemoDataButton : Html Msg
downloadDemoDataButton =
    Html.button
        [ Html.Events.onClick DownloadDemoData, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ]
        [ Html.text "download demo data plz" ]


parseTotalDistanceDisplay : String -> Maybe TotalDistanceDisplay
parseTotalDistanceDisplay v =
    case v of
        "from zero" ->
            Maybe.Just FromZero

        "from last" ->
            Maybe.Just FromLast

        "hide" ->
            Maybe.Just None

        _ ->
            Maybe.Nothing


formatTotalDistanceDisplay : TotalDistanceDisplay -> String
formatTotalDistanceDisplay v =
    case v of
        FromZero ->
            "from zero"

        FromLast ->
            "from last"

        None ->
            "hide"


routeWaypoints : WaypointsOptions -> List Waypoint -> List Waypoint
routeWaypoints waypointOptions waypoints =
    if waypointOptions.locationFilterEnabled then
        List.filter (\w -> Dict.get w.typ waypointOptions.filteredLocationTypes |> Maybe.withDefault True) waypoints

    else
        waypoints


routeBreakdown : List Waypoint -> RouteViewOptions -> Html Msg
routeBreakdown waypoints routeViewOptions =
    let
        info =
            routeInfo waypoints

        svgHeight =
            (*) routeViewOptions.itemSpacing (List.length info)

        svgContentLeftStart =
            0

        svgContentLeftStartString =
            String.fromInt svgContentLeftStart

        lastWaypointDistance =
            List.head (List.reverse waypoints) |> Maybe.map .distance
    in
    Html.div
        [ Svg.Attributes.class "route_breakdown" ]
        [ Svg.svg
            [ Svg.Attributes.width "100%"
            , Svg.Attributes.height <| String.fromInt svgHeight
            , Svg.Attributes.viewBox <| "-120 -10 240 " ++ String.fromInt (svgHeight + routeViewOptions.itemSpacing)
            ]
            (info
                |> List.indexedMap
                    (\i item ->
                        let
                            translate =
                                Svg.Attributes.transform <| "translate(0," ++ (String.fromInt <| i * routeViewOptions.itemSpacing) ++ ")"
                        in
                        case item of
                            InfoWaypoint waypoint ->
                                let
                                    waypointDistance =
                                        case routeViewOptions.totalDistanceDisplay of
                                            None ->
                                                Maybe.Nothing

                                            FromZero ->
                                                Maybe.Just (formatFloat waypoint.distance ++ "km")

                                            FromLast ->
                                                lastWaypointDistance |> Maybe.map (\last -> formatFloat (last - waypoint.distance) ++ "km")

                                    waypointInfo =
                                        List.filterMap identity
                                            [ waypointDistance
                                            , if waypoint.typ /= "" then
                                                Maybe.Just waypoint.typ

                                              else
                                                Maybe.Nothing
                                            ]

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
                                        , Svg.Attributes.y <| String.fromInt (routeViewOptions.itemSpacing // 2)
                                        ]
                                        [ Svg.text waypoint.name ]
                                        :: (waypointInfoLines
                                                |> List.indexedMap
                                                    (\j line ->
                                                        Svg.text_
                                                            [ Svg.Attributes.x svgContentLeftStartString
                                                            , Svg.Attributes.y <| String.fromInt (routeViewOptions.itemSpacing // 2)
                                                            , Svg.Attributes.dominantBaseline "middle"
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
                                    arrowTop =
                                        "2"

                                    arrowBottom =
                                        String.fromInt <| routeViewOptions.itemSpacing - 2

                                    arrowHeadTop =
                                        String.fromInt <| routeViewOptions.itemSpacing - 6

                                    strokeWidth =
                                        "1"
                                in
                                Svg.g [ translate ]
                                    [ Svg.line
                                        [ Svg.Attributes.x1 svgContentLeftStartString
                                        , Svg.Attributes.y1 arrowTop
                                        , Svg.Attributes.x2 svgContentLeftStartString
                                        , Svg.Attributes.y2 arrowBottom
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth strokeWidth
                                        ]
                                        []
                                    , Svg.line
                                        [ Svg.Attributes.x1 <| String.fromInt <| svgContentLeftStart - 2
                                        , Svg.Attributes.y1 <| arrowHeadTop
                                        , Svg.Attributes.x2 <| String.fromInt <| svgContentLeftStart
                                        , Svg.Attributes.y2 arrowBottom
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth strokeWidth
                                        ]
                                        []
                                    , Svg.line
                                        [ Svg.Attributes.x1 <| String.fromInt <| svgContentLeftStart + 2
                                        , Svg.Attributes.y1 <| arrowHeadTop
                                        , Svg.Attributes.x2 <| String.fromInt <| svgContentLeftStart
                                        , Svg.Attributes.y2 arrowBottom
                                        , Svg.Attributes.stroke "grey"
                                        , Svg.Attributes.strokeWidth strokeWidth
                                        ]
                                        []
                                    , Svg.text_
                                        [ Svg.Attributes.x (String.fromInt <| svgContentLeftStart + 10)
                                        , Svg.Attributes.y <| String.fromInt (routeViewOptions.itemSpacing // 2)
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.fontSize "smaller"
                                        ]
                                        [ Svg.text <| formatFloat dist ++ "km" ]
                                    ]
                    )
            )
        ]


routeInfo : List Waypoint -> List Info
routeInfo waypoints =
    List.foldl
        (\el accum ->
            ( Maybe.Just el
            , (InfoWaypoint el
                :: (Tuple.first accum
                        |> Maybe.map (\previous -> [ Ride (el.distance - previous.distance) ])
                        |> Maybe.withDefault []
                   )
              )
                ++ Tuple.second accum
            )
        )
        ( Maybe.Nothing, [] )
        waypoints
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
        , Html.label [ Html.Events.onClick msg ] [ Html.text name ]
        ]


defaultSpacing =
    25



-- STATE
-- The field names in these encoded JSON objects must match exactly the field names
-- in the records of the Model to ensure that deserialising works as expected.


storeModel : Model -> Cmd msg
storeModel model =
    Json.Encode.object
        [ ( "waypoints", model.waypoints |> Maybe.map encodeWaypoints |> Maybe.withDefault Json.Encode.null )
        , ( "totalDistanceDisplay", Json.Encode.string <| formatTotalDistanceDisplay model.routeViewOptions.totalDistanceDisplay )
        , ( "locationFilterEnabled", Json.Encode.bool model.waypointOptions.locationFilterEnabled )
        , ( "filteredLocationTypes", Json.Encode.dict identity Json.Encode.bool model.waypointOptions.filteredLocationTypes )
        , ( "itemSpacing", Json.Encode.int model.routeViewOptions.itemSpacing )
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



--- DEMO DATA


demoData : String
demoData =
    """Distance,Route segment end,Type,Name,Municipality,,Detour,Notes
0,286,,Start,Warwick,,,
99.1,286,🛒,Co-op,Hereford,Big town,,Close 22:00
99.1,286,RS,Something,Hereford,Big town,,Close 22:00
99.1,286,123,Something Else,Hereford,Big town,,Close 22:00
125,286,🛒,Spar,,,,Close 22:00
159,286,🚰,Tap under pub,,,slight,
159,286,RESUPPLY,Fake place,,,slight,
165,286,🛒,Abergavenny Esso,Abergavenny,,slight,24h
230,286,🏙,Bristol,Bristol,City,,
230,286,toilet,Bristol toilet,Bristol,City,,
292.5,585,🛒,Morrisons,Bridgwater,Big town,,Opens 07:00
311.5,585,⛺,Moorhouse Campsite,,,,
336,585,🏙,Minehead,Minehead,,,
408.4,585,🍴,Quay Cafe,,,slight,09:00-17:00
416.5,585,🔄,Detour start A361 bypass,Barnstaple,,,
417,585,🥤,McDonalds,Barnstaple,Big town,,24h
417.5,585,🛒,Tesco,Barnstaple,Big town,,06:00-00:00
435,585,🍴,Griffins Yard,South Molton,Town,Not A316,09:30-17:00
435,585,🛒,Spar,South Molton,Town,,07:00-22:00
435,585,🛒,Esso,South Molton,Town,,06:00-21:00
437,585,⬆,Detour end A361 bypass,South Molton,,,
494,585,🏙,-,Taunton,Big town,,
511,585,☕,Monks Yard Cafe,Ilminster,Small town,slight,09:00-16:00
558.7,585,🥤,Subway,Dorchester,Big town,slight,08:00-18:00
558.7,585,☕,Coffee #1,Dorchester,Big town,slight,
560,585,🛒,Tesco,Dorchester,Big town,,
560,585,🥤,KFC,Dorchester,Big town,,
597.8,827,🔄,Detour start Dorchester,Weymouth,Town,,
599.5,827,🚰,Water fountains,Weymouth,Town,,
633,827,⬆,Detour end Dorchester,,,,
655,827,🔄,Detour start avoid Salisbury,,,,
688,827,⬆,Detour end avoid Salisbury,Amesbury,Town,,
688,827,🛒,Co-op,Amesbury,Town,slight,07:00-22:00
688,827,🥤,Fish & Chips,Amesbury,Town,slight,11:30-20:30
729.6,827,🏙,-,Devizes,Big town,,
732.5,827,❓,Decision: Country road vs A4,Devizes,Big town,,"A4 saves ~15
but may be busy,
goes through big towns"
749,827,🛒,Co-op,Pewsey,Small town,,"Sat: 07-22
Sun: 10-16"
756,827,🛒,Esso,,,,24h
798,827,⬆,A4 rejoin main route,,,,
810,827,🛒,Lidl,"Calcot, Reading",City,,"Sat: 08-22
Sun: 10-16"
813,827,🏙,-,Reading,City,,
817,827,🛒,Tesco (Esso),Reading,City,,07:00-22:30
827.6,944.2,🛒,Sainsburys,Henley,Big town,,07:00-23:00
851.7,944.2,🔄,Detour start Oxford,,,,
882,944.2,⬆,Detour end Oxford,,,,
940,944.2,❗,Join cycle path,,,,
944.2,944.2,,Finish,Warwick,,,
"""
