port module Main exposing (storeState)

import Base64
import Browser
import Browser.Navigation
import Bytes
import Bytes.Decode
import Bytes.Encode
import Csv.Decode
import Dict
import Dropdown
import File
import File.Download
import File.Select
import Flate
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Json.Encode
import QRCode
import Round
import String
import Svg
import Svg.Attributes
import Task
import Time
import Url exposing (Protocol(..))
import Url.Builder
import Url.Parser exposing ((</>), (<?>))
import Url.Parser.Query



-- MAIN


main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = always <| Time.every 1500 (always Tick)
        , onUrlRequest = \_ -> Never
        , onUrlChange = \_ -> Never
        }



-- MODEL


type alias StoredState =
    { waypoints : Maybe (List Waypoint)
    , totalDistanceDisplay : Maybe String
    , locationFilterEnabled : Maybe Bool
    , filteredLocationTypes : Maybe (Dict.Dict String Bool)
    , itemSpacing : Maybe Int
    , distanceDetail : Maybe Int
    }


type alias Model =
    { page : Page
    , csvDecodeError : Maybe String
    , showOptions : Bool
    , routeViewOptions : RouteViewOptions
    , showQR : Bool
    , url : Url.Url
    }


type Page
    = WelcomePage Bool
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


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState url key =
    let
        queryState =
            -- snap the url path to empty to skip handling of url segments
            Url.Parser.parse (Url.Parser.query (Url.Parser.Query.string "state")) { url | path = "" }
                |> Maybe.withDefault Maybe.Nothing
                |> Maybe.andThen Base64.toBytes
                |> Maybe.andThen Flate.inflateGZip
                -- example from https://package.elm-lang.org/packages/folkertdev/elm-flate/latest/Flate
                |> Maybe.andThen (\buf -> Bytes.Decode.decode (Bytes.Decode.string (Bytes.width buf)) buf)
                -- TODO: handle decode error, get user to send me the state
                |> Maybe.andThen (Json.Decode.decodeString (storedStateDecoder shortFieldNames) >> Result.toMaybe)
    in
    (case queryState of
        Just storedState ->
            storedStateModel url storedState

        Nothing ->
            maybeState
                |> Maybe.map
                    (Json.Decode.decodeValue (storedStateDecoder longFieldNames)
                        -- TODO: handle error
                        >> Result.withDefault (StoredState Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing)
                        >> storedStateModel url
                    )
                |> Maybe.withDefault (Model (WelcomePage False) Maybe.Nothing True (RouteViewOptions FromZero defaultSpacing defaultDistanceDetail) False url)
    )
        |> updateModel
        |> Tuple.mapSecond
            (\cmd ->
                -- if state from query was successful, remove query from URL
                (queryState |> Maybe.map (always (Browser.Navigation.replaceUrl key <| Url.toString { url | query = Maybe.Nothing })))
                    |> Maybe.map List.singleton
                    |> Maybe.withDefault []
                    |> (::) cmd
                    |> Cmd.batch
            )


storedStateModel : Url.Url -> StoredState -> Model
storedStateModel url state =
    Model
        (state.waypoints
            |> Maybe.map
                (\ws ->
                    RouteModel ws
                        (WaypointsOptions
                            (state.locationFilterEnabled |> Maybe.withDefault False)
                            (state.filteredLocationTypes |> Maybe.withDefault (initialFilteredLocations ws))
                        )
                        |> RoutePage
                )
            |> Maybe.withDefault (WelcomePage False)
        )
        Maybe.Nothing
        True
        (RouteViewOptions
            (state.totalDistanceDisplay |> Maybe.andThen parseTotalDistanceDisplay |> Maybe.withDefault FromZero)
            (Maybe.withDefault defaultSpacing state.itemSpacing)
            (Maybe.withDefault defaultDistanceDetail state.distanceDetail)
        )
        False
        url


type Msg
    = Never
    | ShowPage Page
    | TypeEnabled String Bool
    | ShowOptions Bool
    | UpdateTotalDistanceDisplay (Maybe TotalDistanceDisplay)
    | UpdateWaypointSelection (Maybe Bool)
    | UpdateItemSpacing Int
    | UpdateDistanceDetail Int
    | OpenFileBrowser
    | FileUploaded File.File
    | CsvDecoded (Result Csv.Decode.Error (List Waypoint))
    | LoadDemoData
    | DownloadDemoData
    | ShowQR
    | CloseQR
    | Tick


initialWaypointOptions : List Waypoint -> WaypointsOptions
initialWaypointOptions waypoints =
    WaypointsOptions False (initialFilteredLocations waypoints)


initialFilteredLocations : List Waypoint -> Dict.Dict String Bool
initialFilteredLocations waypoints =
    List.map (\el -> ( el.typ, True )) waypoints |> Dict.fromList


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ShowPage page ->
            updateModel { model | page = page }

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

        ShowOptions show ->
            ( { model | showOptions = show }, Cmd.none )

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
            updateCSVDecodeModel model result

        LoadDemoData ->
            decodeCSV demoData |> updateCSVDecodeModel model

        DownloadDemoData ->
            ( model, File.Download.string "demo-data.csv" "text/csv" demoData )

        ShowQR ->
            updateModel { model | showQR = True }

        CloseQR ->
            updateModel { model | showQR = False }

        Never ->
            ( model, Cmd.none )

        Tick ->
            case model.page of
                WelcomePage val ->
                    ( { model | page = WelcomePage (not val) }, Cmd.none )

                _ ->
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
    let
        localStoredState =
            encodeSavedState longFieldNames model
    in
    ( model, storeState localStoredState )


updateCSVDecodeModel : Model -> Result Csv.Decode.Error (List Waypoint) -> ( Model, Cmd Msg )
updateCSVDecodeModel model result =
    case result of
        Ok waypoints ->
            { model | page = RoutePage <| initialRouteModel waypoints } |> updateModel

        Err err ->
            ( { model | csvDecodeError = Maybe.Just <| Csv.Decode.errorToString err }, Cmd.none )


initialRouteModel : List Waypoint -> RouteModel
initialRouteModel waypoints =
    let
        sortedWaypoint =
            List.sortBy .distance waypoints
    in
    RouteModel sortedWaypoint (initialWaypointOptions sortedWaypoint)



-- VIEW


view : Model -> Browser.Document Msg
view model =
    -- TODO: better title plz
    Browser.Document "Route sheet"
        [ case model.page of
            RoutePage routeModel ->
                if model.showQR then
                    Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "column"
                        , Html.Attributes.class "page"
                        , Html.Attributes.style "height" "100%"
                        , Html.Attributes.style "justify-content" "center"
                        , Html.Attributes.style "align-items" "center"
                        ]
                        (encodeSavedState shortFieldNames model
                            |> Bytes.Encode.string
                            |> Bytes.Encode.encode
                            |> Flate.deflateGZip
                            |> Base64.fromBytes
                            |> Maybe.map (stateUrl model.url)
                            |> Maybe.map
                                (\url ->
                                    -- WEBrick has max URL length of around 2090 (form local testing), picking 1800 as max to be safe
                                    if String.length url > 1800 then
                                        [ viewErrorPanel "😞 the URL created for sharing would be too long for the current method,\n\nplease let me know and I will work out a new way to do this!" ]

                                    else
                                        QRCode.fromStringWith QRCode.Medium url
                                            |> Result.map
                                                (\qr ->
                                                    [ QRCode.toSvg [ Svg.Attributes.width "500", Svg.Attributes.height "500" ] qr
                                                    , Html.br [] []
                                                    , Html.p [] [ Html.text "Scan the QR code above on your device" ]
                                                    , Html.p [] [ Html.text "and follow the link to load in the current route." ]
                                                    , Html.br [] []
                                                    , Html.p [] [ Html.text "Alternatively, copy this link and send to your device through some other means..." ]
                                                    , Html.br [] []
                                                    , Html.p
                                                        [ Html.Attributes.style "word-break" "break-all"
                                                        , Html.Attributes.style "white-space" "normal"
                                                        ]
                                                        [ Html.text url ]
                                                    ]
                                                )
                                            |> Result.mapError
                                                (\err ->
                                                    case err of
                                                        QRCode.AlignmentPatternNotFound ->
                                                            [ viewErrorPanel "😞 there was an error encoding your share code, please contact me and give me this state error: AlignmentPatternNotFound" ]

                                                        QRCode.InvalidNumericChar ->
                                                            [ viewErrorPanel "😞 there was an error encoding your share code, please contact me and give me this state error: InvalidNumericChar" ]

                                                        QRCode.InvalidAlphanumericChar ->
                                                            [ viewErrorPanel "😞 there was an error encoding your share code, please contact me and give me this state error: InvalidAlphanumericChar" ]

                                                        QRCode.InvalidUTF8Char ->
                                                            [ viewErrorPanel "😞 there was an error encoding your share code, please contact me and give me this state error: InvalidUTF8Char" ]

                                                        QRCode.LogTableException table ->
                                                            [ viewErrorPanel "😞 there was an error encoding your share code, please contact me and give me this state error: LogTableException" ]

                                                        QRCode.PolynomialMultiplyException ->
                                                            [ viewErrorPanel "😞 there was an error encoding your share code, please contact me and give me this state error: PolynomialMultiplyException" ]

                                                        QRCode.PolynomialModException ->
                                                            [ viewErrorPanel "😞 there was an error encoding your share code, please contact me and give me this state error: PolynomialModException" ]

                                                        QRCode.InputLengthOverflow ->
                                                            [ viewErrorPanel "😞 sadly the data you are using is too large for the current sharing mechanism.\n\nPlease contact me and I will try to rectify the issue!" ]
                                                )
                                            |> resultCollect
                                )
                            -- error with creating base64 bytes, should never happen according to the docs
                            |> Maybe.withDefault [ viewErrorPanel "😞 there was an error preparing your QR code, so sorry.\n\nPlease contact me and I will try to rectify the issue!" ]
                            |> (\els ->
                                    els
                                        ++ [ Html.br [] []
                                           , Html.button
                                                [ Html.Events.onClick CloseQR, Html.Attributes.class "button-4" ]
                                                [ Html.text "Close" ]
                                           ]
                               )
                        )

                else
                    Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "row"
                        , Html.Attributes.class "page"
                        , Html.Attributes.style "height" "100%"
                        ]
                        [ viewOptions model.showOptions routeModel.waypointOptions model.routeViewOptions model.csvDecodeError
                        , Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.class "wide"
                            , Html.Attributes.style "height" "100%"
                            , Html.Attributes.style "justify-content" "center"
                            ]
                            [ routeBreakdown (routeWaypoints routeModel.waypointOptions routeModel.waypoints) model.routeViewOptions
                            ]
                        ]

            WelcomePage val ->
                welcomePage val

            GetStartedPage ->
                getStartedPage model.csvDecodeError
        ]


resultCollect : Result a a -> a
resultCollect res =
    case res of
        Ok ok ->
            ok

        Err err ->
            err


stateUrl : Url.Url -> String -> String
stateUrl url encodedState =
    Url.toString
        { url
          --drop first letter of query which is '?' and gets prepended again by the Url.toString call
            | query = encodedState |> Url.Builder.string "state" |> List.singleton |> Url.Builder.toQuery |> String.dropLeft 1 |> Maybe.Just
        }


welcomePage : Bool -> Html Msg
welcomePage toGo =
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
        (List.concat
            [ [ Html.h2 [] [ Html.text "Route breakdown builder" ]
              , Html.br [] []
              , Html.h3 [] [ Html.text "Features" ]
              , Html.br [] []
              , Html.ul []
                    [ Html.li [] [ Html.text "Customise information level" ]
                    , Html.li [] [ Html.text "Compact or spacious view" ]
                    , Html.li [] [ Html.text "User-defined location types" ]
                    , Html.li [] [ Html.text "Filter location types" ]
                    , Html.li [] [ Html.text "Design on desktop, send to device" ]
                    , Html.li [] [ Html.text "...and more." ]
                    ]
              , Html.br [] []
              , Html.br [] []
              , viewButton "Get started..." <| ShowPage GetStartedPage
              , Html.br [] []
              , viewButton "...play with demo..." LoadDemoData
              , Html.br [] []
              , Html.br [] []
              , Html.h3 [] [ Html.text "...or see some examples" ]
              , Html.br [] []
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
                        [ if toGo then
                            ( "Distance to go", identity, RouteViewOptions FromLast defaultSpacing defaultDistanceDetail )

                          else
                            ( "Distance from zero", identity, RouteViewOptions FromZero defaultSpacing defaultDistanceDetail )
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
            ]
        )


getStartedPage : Maybe String -> Html Msg
getStartedPage decodeError =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "flex-center"
        , Html.Attributes.class "column"
        ]
        (List.concat
            [ [ Html.h2 [] [ Html.text "Route breakdown builder" ]
              , Html.br [] []
              , Html.h3 [] [ Html.text "Instructions" ]
              , Html.br [] []
              , Html.p [] [ Html.text "To make your route breakdown," ]
              , Html.p [] [ Html.text "upload a CSV file with the following columns, including title at top" ]
              , Html.p [] [ Html.text "and a row per waypoint:" ]
              , Html.br [] []
              , Html.ul []
                    [ Html.li [] [ Html.b [] [ Html.text "\"Type\"" ], Html.text " - Supports emojis, advice is to keep it short." ]
                    , Html.li [] [ Html.b [] [ Html.text "\"Distance\"" ], Html.text " - Just the number, no units." ]
                    , Html.li [] [ Html.b [] [ Html.text "\"Name\"" ], Html.text " - Supports emojis." ]
                    ]
              , Html.br [] []
              , viewButton "upload waypoints" OpenFileBrowser
              ]
            , decodeError |> Maybe.map (\err -> [ Html.br [] [], viewCSVDecodeErrorPanel err ]) |> Maybe.withDefault []
            , [ Html.br [] []
              , Html.p [] [ Html.text "CSV can be downloaded from Google Sheets or exported from Excel." ]
              , Html.p [] [ Html.text "For an example file, please click the button below." ]
              , Html.br [] []
              , viewButton "download example CSV" DownloadDemoData
              , Html.br [] []
              , Html.h3 [] [ Html.text "...or play with a demo and see some examples" ]
              , Html.br [] []
              , viewButton "play with demo" LoadDemoData
              , Html.br [] []
              , Html.br [] []
              ]
            ]
        )


optionGroup : String -> List (Html Msg) -> Html Msg
optionGroup title elements =
    Html.div [ Html.Attributes.class "flex-container", Html.Attributes.class "column" ]
        (Html.legend [] [ Html.text title ] :: elements)


viewOptions : Bool -> WaypointsOptions -> RouteViewOptions -> Maybe String -> Html Msg
viewOptions show waypointOptions routeViewOptions decodeError =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "justify-content" "center"
        , Html.Attributes.style "overflow" "auto"
        , Html.Attributes.class "narrow"
        ]
        (if not show then
            [ Html.p
                [ Html.Events.onClick <| ShowOptions True
                , Html.Attributes.style "transform" "rotate(90deg)"
                , Html.Attributes.style "white-space" "nowrap"
                , Html.Attributes.style "width" "1em"
                ]
                [ Html.text "(show options)" ]
            ]

         else
            List.concat
                [ [ Html.div [ Html.Attributes.class "options" ] <|
                        [ Html.h2 [] [ Html.text "Options" ]
                        , Html.p [ Html.Events.onClick <| ShowOptions False ] [ Html.text "(hide)" ]
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
                        , Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.style "justify-content" "center"
                            , Html.Attributes.style "align-items" "center"
                            ]
                            [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "upload waypoints" OpenFileBrowser
                            , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "clear" (ShowPage <| WelcomePage False)
                            , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "share / send to device" ShowQR
                            ]
                        ]
                  ]
                , decodeError |> Maybe.map (\err -> [ Html.br [] [], viewCSVDecodeErrorPanel err ]) |> Maybe.withDefault [ Html.div [] [] ]
                ]
        )


viewCSVDecodeErrorPanel : String -> Html Msg
viewCSVDecodeErrorPanel error =
    viewErrorPanel <| ("There was an error decoding your CSV. Please fix any error and try again 😇\n\nThe first few errors can be seen below.\n\n" ++ String.left 1000 error ++ "...")


viewErrorPanel : String -> Html Msg
viewErrorPanel error =
    Html.div [ Html.Attributes.class "error_panel" ] [ Html.text error ]


viewButton : String -> Msg -> Html Msg
viewButton text msg =
    viewButtonWithAttributes [] text msg


viewButtonWithAttributes : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButtonWithAttributes attrs text msg =
    Html.button
        ([ Html.Events.onClick msg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


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


type alias StoredStateCodeFields =
    { waypoints : String
    , waypointName : String
    , waypointDistance : String
    , waypointType : String
    , totalDistanceDisplay : String
    , distanceDetail : String
    , locationFilterEnabled : String
    , filteredLocationTypes : String
    , itemSpacing : String
    }


longFieldNames : StoredStateCodeFields
longFieldNames =
    { waypoints = "waypoints"
    , waypointName = "name"
    , waypointDistance = "distance"
    , waypointType = "typ"
    , totalDistanceDisplay = "totalDistanceDisplay"
    , distanceDetail = "distanceDetail"
    , locationFilterEnabled = "locationFilterEnabled"
    , filteredLocationTypes = "filteredLocationTypes"
    , itemSpacing = "itemSpacing"
    }


{-| shortFieldNames are used within the QR code to reduce the payload size,
as when the state is transferred as a query param it's easy to overload
the server used under the hood for jekyll and get the following error
which results in a 404:
ERROR WEBrick::HTTPStatus::RequestURITooLarge
-}
shortFieldNames : StoredStateCodeFields
shortFieldNames =
    { waypoints = "w"
    , waypointName = "n"
    , waypointDistance = "d"
    , waypointType = "t"
    , totalDistanceDisplay = "tdd"
    , distanceDetail = "dd"
    , locationFilterEnabled = "lfe"
    , filteredLocationTypes = "flt"
    , itemSpacing = "is"
    }


encodeSavedState : StoredStateCodeFields -> Model -> String
encodeSavedState fieldNames model =
    Json.Encode.object
        ((case model.page of
            RoutePage routeModel ->
                [ ( fieldNames.waypoints, encodeWaypoints fieldNames routeModel.waypoints )
                , ( fieldNames.locationFilterEnabled, Json.Encode.bool routeModel.waypointOptions.locationFilterEnabled )
                , ( fieldNames.filteredLocationTypes, Json.Encode.dict identity Json.Encode.bool routeModel.waypointOptions.filteredLocationTypes )
                ]

            _ ->
                []
         )
            ++ [ ( fieldNames.totalDistanceDisplay, Json.Encode.string <| formatTotalDistanceDisplay model.routeViewOptions.totalDistanceDisplay )
               , ( fieldNames.distanceDetail, Json.Encode.int model.routeViewOptions.distanceDetail )
               , ( fieldNames.itemSpacing, Json.Encode.int model.routeViewOptions.itemSpacing )
               ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : StoredStateCodeFields -> Json.Decode.Decoder StoredState
storedStateDecoder fieldNames =
    Json.Decode.map6 StoredState
        (Json.Decode.maybe (Json.Decode.field fieldNames.waypoints (decodeWaypoints fieldNames)))
        (Json.Decode.maybe (Json.Decode.field fieldNames.totalDistanceDisplay Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field fieldNames.locationFilterEnabled Json.Decode.bool))
        (Json.Decode.maybe (Json.Decode.field fieldNames.filteredLocationTypes (Json.Decode.dict Json.Decode.bool)))
        (Json.Decode.maybe (Json.Decode.field fieldNames.itemSpacing Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field fieldNames.distanceDetail Json.Decode.int))


decodeWaypoints : StoredStateCodeFields -> Json.Decode.Decoder (List Waypoint)
decodeWaypoints fieldNames =
    Json.Decode.list
        (Json.Decode.map3 Waypoint
            (Json.Decode.field fieldNames.waypointName Json.Decode.string)
            (Json.Decode.field fieldNames.waypointDistance Json.Decode.float)
            (Json.Decode.field fieldNames.waypointType Json.Decode.string)
        )


encodeWaypoints : StoredStateCodeFields -> List Waypoint -> Json.Encode.Value
encodeWaypoints fieldNames waypoints =
    Json.Encode.list
        (\waypoint ->
            Json.Encode.object
                [ ( fieldNames.waypointName, Json.Encode.string waypoint.name )
                , ( fieldNames.waypointDistance, Json.Encode.float waypoint.distance )
                , ( fieldNames.waypointType, Json.Encode.string waypoint.typ )
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
