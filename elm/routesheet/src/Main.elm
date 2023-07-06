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
import Round
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
    , locationFilterEnabled : Maybe Bool
    , filteredLocationTypes : Maybe Json.Decode.Value
    , itemSpacing : Int
    , distanceDetail : Int
    }


type alias Model =
    { page : Page
    , routeViewOptions : RouteViewOptions
    }


type Page
    = WelcomePage
    | GetStartedPage
    | RoutePage RouteModel


type alias RouteModel =
    { waypoints : List Waypoint
    , waypointOptions : WaypointsOptions
    }


type alias WaypointsOptions =
    { -- TODO: combine filter enabled and dict into single Maybe then deserialise from null or object
      locationFilterEnabled : Bool
    , filteredLocationTypes : Dict.Dict String Bool
    }


type alias RouteViewOptions =
    { totalDistanceDisplay : TotalDistanceDisplay
    , itemSpacing : Int
    , distanceDetail : Int
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
    case maybeState of
        Nothing ->
            ( Model WelcomePage (RouteViewOptions FromZero defaultSpacing defaultDistanceDetail), Cmd.none )

        Just state ->
            let
                page =
                    state.waypoints
                        |> Maybe.map
                            (\ws ->
                                RoutePage
                                    (RouteModel ws
                                        (WaypointsOptions
                                            (state.locationFilterEnabled |> Maybe.withDefault False)
                                            (state.filteredLocationTypes
                                                |> Maybe.map
                                                    (Json.Decode.decodeValue (Json.Decode.dict Json.Decode.bool)
                                                        -- if error during decode of filtered types, reset filter based on waypoints
                                                        >> Result.withDefault (initialFilteredLocations ws)
                                                    )
                                                |> Maybe.withDefault (initialFilteredLocations ws)
                                            )
                                        )
                                    )
                            )
                        |> Maybe.withDefault WelcomePage
            in
            ( Model page (RouteViewOptions (parseTotalDistanceDisplay state.totalDistanceDisplay |> Maybe.withDefault FromZero) state.itemSpacing state.distanceDetail), Cmd.none )


type Msg
    = Never
    | TypeEnabled String Bool
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdateWaypointSelection (Maybe Bool)
    | UpdateItemSpacing Int
    | UpdateDistanceDetail Int
    | OpenFileBrowser
    | FileUploaded File.File
    | CsvDecoded (Result Csv.Decode.Error (List Waypoint))
    | GetStarted
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
            case model.page of
                RoutePage routeModel ->
                    let
                        options =
                            routeModel.waypointOptions

                        newRouteModel =
                            { routeModel | waypointOptions = { options | filteredLocationTypes = Dict.insert typ enabled routeModel.waypointOptions.filteredLocationTypes } }
                    in
                    updateRouteModel model newRouteModel

                _ ->
                    ( model, Cmd.none )

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
            case model.page of
                RoutePage routeModel ->
                    maybeSelection
                        |> Maybe.map
                            (\locationFilterEnabled ->
                                let
                                    options =
                                        routeModel.waypointOptions

                                    newRouteModel =
                                        { routeModel | waypointOptions = { options | locationFilterEnabled = locationFilterEnabled } }
                                in
                                updateRouteModel model newRouteModel
                            )
                        |> Maybe.withDefault ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        UpdateItemSpacing spacing ->
            let
                options =
                    model.routeViewOptions
            in
            updateModel { model | routeViewOptions = { options | itemSpacing = spacing } }

        UpdateDistanceDetail detail ->
            let
                options =
                    model.routeViewOptions
            in
            updateModel { model | routeViewOptions = { options | distanceDetail = detail } }

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
                |> Result.map (initialModel >> updateRouteModel model)
                --TODO: handle decode error
                |> Result.withDefault ( model, Cmd.none )

        GetStarted ->
            ( { model | page = GetStartedPage }, Cmd.none )

        LoadDemoData ->
            decodeCSV demoData
                |> Result.map (initialModel >> updateRouteModel model)
                --TODO: handle decode error
                |> Result.withDefault ( model, Cmd.none )

        DownloadDemoData ->
            ( model, File.Download.string "demo-data.csv" "text/csv" demoData )

        ClearWaypoints ->
            updateModel { model | page = WelcomePage }

        Never ->
            ( model, Cmd.none )


updateRouteModel : Model -> RouteModel -> ( Model, Cmd Msg )
updateRouteModel model routeModel =
    updateModel <| { model | page = RoutePage routeModel }


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


initialModel : List Waypoint -> RouteModel
initialModel waypoints =
    let
        sortedWaypoint =
            List.sortBy .distance waypoints
    in
    RouteModel sortedWaypoint (initialWaypointOptions sortedWaypoint)



-- VIEW


view : Model -> Browser.Document Msg
view model =
    Browser.Document "Route sheet"
        [ case model.page of
            RoutePage routeModel ->
                routeModel.waypoints
                    |> (\w ->
                            Html.div
                                [ Html.Attributes.class "flex-container"
                                , Html.Attributes.class "row"
                                , Html.Attributes.class "page"
                                , Html.Attributes.style "height" "100%"
                                ]
                                [ viewOptions routeModel.waypointOptions model.routeViewOptions
                                , Html.div
                                    [ Html.Attributes.class "flex-container"
                                    , Html.Attributes.class "column"
                                    , Html.Attributes.class "wide"
                                    , Html.Attributes.style "height" "100%"
                                    , Html.Attributes.style "justify-content" "center"
                                    ]
                                    [ routeBreakdown (routeWaypoints routeModel.waypointOptions w) model.routeViewOptions
                                    ]
                                ]
                       )

            WelcomePage ->
                welcomePage

            GetStartedPage ->
                getStartedPage
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
        ]
        [ Html.h2 [] [ Html.text "Route breakdown builder" ]
        , Html.br [] []
        , Html.h3 [] [ Html.text "Features" ]
        , Html.br [] []
        , Html.ul []
            [ Html.li [] [ Html.text "Customise information level" ]
            , Html.li [] [ Html.text "Compact or spacious view" ]
            , Html.li [] [ Html.text "User-defined location types" ]
            , Html.li [] [ Html.text "Filter location types" ]
            , Html.li [] [ Html.text "...and more." ]
            ]
        , Html.br [] []
        , Html.h3 [] [ Html.text "Get started..." ]
        , Html.br [] []
        , getStartedButton
        , Html.br [] []
        , Html.h3 [] [ Html.text "...play with a demo..." ]
        , Html.br [] []
        , loadDemoDataButton
        , Html.br [] []
        , Html.h3 [] [ Html.text "...or see some examples" ]
        , Html.br [] []
        , Html.div
            [ Html.Attributes.style "width" "100%"
            , Html.Attributes.style "justify-content" "space-evenly"
            , Html.Attributes.class "flex-container"
            , Html.Attributes.class "flex-center"
            , Html.Attributes.class "flex-wrap"
            , Html.Attributes.class "wide-row-narrow-column"
            ]
            (List.map (\( desc, waypointModifier, opts ) -> Html.div [] [ Html.h4 [ Html.Attributes.style "text-align" "center" ] [ Html.text desc ], routeBreakdown (waypointModifier exampleWaypoints) opts ])
                [ ( "Distance from zero", identity, RouteViewOptions FromZero defaultSpacing defaultDistanceDetail )
                , ( "Distance to go"
                  , identity
                  , RouteViewOptions
                        FromLast
                        defaultSpacing
                        defaultDistanceDetail
                  )
                , ( "Custom location types"
                  , List.map
                        (\w ->
                            { w
                                | typ =
                                    Dict.get w.typ (Dict.fromList [ ( cafeType, "☕" ), ( climbType, "⛰️" ) ])
                                        |> Maybe.withDefault ""
                            }
                        )
                  , RouteViewOptions None defaultSpacing defaultDistanceDetail
                  )
                , ( "Custom spacing", identity, RouteViewOptions None (defaultSpacing - 10) defaultDistanceDetail )
                , ( "Filter location types", routeWaypoints (WaypointsOptions True (initialFilteredLocations exampleWaypoints |> Dict.map (\k _ -> k == climbType || k == ""))), RouteViewOptions None defaultSpacing defaultDistanceDetail )
                ]
            )
        ]


getStartedPage : Html Msg
getStartedPage =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "flex-center"
        , Html.Attributes.class "column"
        ]
        [ Html.h2 [] [ Html.text "Route breakdown builder" ]
        , Html.br [] []
        , Html.h3 [] [ Html.text "Instructions" ]
        , Html.br [] []
        , Html.p [] [ Html.text "To make your route breakdown," ]
        , Html.p [] [ Html.text "upload a CSV file with the following columns, including title at top:" ]
        , Html.p [] [ Html.text "and a row per waypoint:" ]
        , Html.br [] []
        , Html.ul []
            [ Html.ul [] [ Html.b [] [ Html.text "\"Type\"" ], Html.text " - Supports emojis, advice is to keep it short." ]
            , Html.ul [] [ Html.b [] [ Html.text "\"Distance\"" ], Html.text " - Just the number, no units." ]
            , Html.ul [] [ Html.b [] [ Html.text "\"Name\"" ], Html.text " - Supports emojis." ]
            ]
        , Html.br [] []
        , viewUploadButton
        , Html.br [] []
        , Html.p [] [ Html.text "CSV can be downloaded from Google Sheets or exported from Excel." ]
        , Html.p [] [ Html.text "For an example file, please click the button below." ]
        , Html.br [] []
        , downloadDemoDataButton
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
            , optionGroup "Distance detail"
                [ Html.input
                    [ Html.Attributes.type_ "range"
                    , Html.Attributes.min "0"
                    , Html.Attributes.max "3"
                    , Html.Attributes.value <| String.fromInt routeViewOptions.distanceDetail
                    , Html.Events.onInput (String.toInt >> Maybe.withDefault defaultDistanceDetail >> UpdateDistanceDetail)
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


getStartedButton : Html Msg
getStartedButton =
    Html.button
        [ Html.Events.onClick GetStarted, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ]
        [ Html.text "get started" ]


loadDemoDataButton : Html Msg
loadDemoDataButton =
    Html.button
        [ Html.Events.onClick LoadDemoData, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ]
        [ Html.text "play with demo" ]


downloadDemoDataButton : Html Msg
downloadDemoDataButton =
    Html.button
        [ Html.Events.onClick DownloadDemoData, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ]
        [ Html.text "download example CSV" ]


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
        [ Html.Attributes.class "route_breakdown"
        ]
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
                                                Maybe.Just (formatFloat routeViewOptions.distanceDetail waypoint.distance ++ "km")

                                            FromLast ->
                                                lastWaypointDistance |> Maybe.map (\last -> formatFloat routeViewOptions.distanceDetail (last - waypoint.distance) ++ "km")

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
                                        [ Svg.text <| formatFloat routeViewOptions.distanceDetail dist ++ "km" ]
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


formatFloat : Int -> Float -> String
formatFloat decimalPlaces value =
    Round.round decimalPlaces value


checkbox : Bool -> msg -> String -> Html msg
checkbox b msg name =
    Html.div []
        [ Html.input [ Html.Attributes.type_ "checkbox", Html.Events.onClick msg, Html.Attributes.checked b ] []
        , Html.label [ Html.Events.onClick msg ] [ Html.text name ]
        ]


defaultSpacing =
    25


defaultDistanceDetail =
    1



-- STATE
-- The field names in these encoded JSON objects must match exactly the field names
-- in the records of the Model to ensure that deserialising works as expected.


storeModel : Model -> Cmd msg
storeModel model =
    Json.Encode.object
        (List.concat
            [ case model.page of
                RoutePage routeModel ->
                    [ ( "waypoints", encodeWaypoints routeModel.waypoints )
                    , ( "locationFilterEnabled", Json.Encode.bool routeModel.waypointOptions.locationFilterEnabled )
                    , ( "filteredLocationTypes", Json.Encode.dict identity Json.Encode.bool routeModel.waypointOptions.filteredLocationTypes )
                    ]

                _ ->
                    []
            , [ ( "totalDistanceDisplay", Json.Encode.string <| formatTotalDistanceDisplay model.routeViewOptions.totalDistanceDisplay )
              , ( "distanceDetail", Json.Encode.int model.routeViewOptions.distanceDetail )
              , ( "itemSpacing", Json.Encode.int model.routeViewOptions.itemSpacing )
              ]
            ]
        )
        |> Json.Encode.encode 2
        |> storeState


encodeWaypoints : List Waypoint -> Json.Encode.Value
encodeWaypoints waypoints =
    Json.Encode.list
        (\waypoint ->
            Json.Encode.object
                Json.Decode.nullable
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
125,286,RS,Kwik-E-Mart,,,,Close 22:00
292.5,585,RS,Morrisons,Bridgwater,Big town,,Opens 07:00
311.5,585,⛺,Moorhouse Campsite,,,,
408.4,585,🍴,Quay Cafe,,,slight,09:00-17:00
417,585,RS,Des' Veg,South Molton,Town,,06:00-21:00
435,585,🍴,Griffins Yard,South Molton,Town,Not A316,09:30-17:00
437,585,❗,Detour end A361 bypass,South Molton,,,
511,585,🍴,Monks Yard Cafe,Ilminster,Small town,slight,09:00-16:00
558.7,585,🥤,Subway,Dorchester,Big town,slight,08:00-18:00
560,585,RS,Co-op,Dorchester,Big town,,
599.5,827,🚰,Water fountains,Weymouth,Town,,
633,827,❗,Detour end Dorchester,,,,
655,827,❗,Detour start avoid Salisbury,,,,
688,827,❗,Detour end avoid Salisbury,Amesbury,Town,,
688,827,🥤,Fish & Chips,Amesbury,Town,slight,11:30-20:30
732.5,827,❗,Decision: Country road vs A4,Devizes,Big town,,"A4 saves ~15
but may be busy,
goes through big towns"
749,827,RS,Co-op,Pewsey,Small town,,"Sat: 07-22
Sun: 10-16"
798,827,❗,A4 rejoin main route,,,,
827.6,944.2,RS,Sainos,Henley,Big town,,07:00-23:00
940,944.2,❗,Join cycle path,,,,
944.2,944.2,,Finish,Warwick,,,
"""
