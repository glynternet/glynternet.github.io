port module Main exposing (storeState)

import Base64
import Browser
import Browser.Navigation
import Bytes
import Bytes.Decode
import Bytes.Encode
import Dict
import Dropdown
import File
import File.Select
import Flate
import GpxApi
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
    , lastReferencePoint : Maybe Float
    , locationFilterEnabled : Maybe Bool
    , filteredLocationTypes : Maybe (Dict.Dict String Bool)
    , itemSpacing : Maybe Int
    , distanceDetail : Maybe Int
    , showOptions : Maybe Bool
    }


type alias Model =
    { page : Page
    , gpxError : Maybe String
    , gpxServerURLOverride : Maybe String
    , showOptions : Bool
    , cuesViewOptions : CuesViewOptions
    , showQR : Bool
    , url : Url.Url
    }


type Page
    = WelcomePage Bool
    | GetStartedPage
    | CuesheetPage CuesModel


type alias CuesModel =
    { waypoints : List Waypoint
    , waypointOptions : WaypointsOptions
    }


type alias WaypointsOptions =
    { -- TODO: combine filter enabled and dict into single Maybe then deserialise from null or object
      locationFilterEnabled : Bool
    , filteredLocationTypes : Dict.Dict String Bool
    }


type alias CuesViewOptions =
    { totalDistanceDisplay : TotalDistanceDisplay
    , referencePoint : Float
    , position : Float
    , itemSpacing : Int
    , distanceDetail : Int
    }


type TotalDistanceDisplay
    = FromZero
    | ToLast
    | ToPoint
    | None


type alias Waypoint =
    { name : String
    , distance : Float
    , types : List String
    }


unknownType =
    ""


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
                        >> Result.withDefault (StoredState Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing Maybe.Nothing)
                        >> storedStateModel url
                    )
                -- TODO(glynternet): best default value for last reference point/?
                |> Maybe.withDefault (Model (WelcomePage False) Maybe.Nothing Maybe.Nothing True (CuesViewOptions FromZero 1000 0 defaultSpacing defaultDistanceDetail) False url)
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
                    CuesModel ws
                        (WaypointsOptions
                            (state.locationFilterEnabled |> Maybe.withDefault False)
                            (state.filteredLocationTypes |> Maybe.withDefault (initialFilteredLocations ws))
                        )
                        |> CuesheetPage
                )
            |> Maybe.withDefault (WelcomePage False)
        )
        Maybe.Nothing
        Maybe.Nothing
        (state.showOptions |> Maybe.withDefault True)
        (CuesViewOptions
            -- TODO(glynternet): store "to point" state
            (state.totalDistanceDisplay |> Maybe.andThen (parseTotalDistanceDisplay Maybe.Nothing) |> Maybe.withDefault FromZero)
            (state.lastReferencePoint |> Maybe.withDefault 1000)
            -- TODO(glynternet): best default or getting last point here?
            0
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
    | UpdateFilterEnabled Bool
    | UpdatePosition Float
    | UpdateReferencePoint Float
    | UpdateItemSpacing Int
    | UpdateDistanceDetail Int
    | OpenFileBrowser
    | FileUploaded File.File
    | GpxResponseReceived (Result String (List GpxApi.Track))
    | ShowQR
    | CloseQR
    | Tick


initialWaypointOptions : List Waypoint -> WaypointsOptions
initialWaypointOptions waypoints =
    WaypointsOptions False (initialFilteredLocations waypoints)


initialFilteredLocations : List Waypoint -> Dict.Dict String Bool
initialFilteredLocations =
    List.foldl
        (\el ( waypointsIterationCurrent, includeUnknown ) ->
            if List.isEmpty el.types then
                ( waypointsIterationCurrent, True )

            else
                ( List.foldl
                    (\typ waypointIterationCurrent -> Dict.insert typ True waypointIterationCurrent)
                    waypointsIterationCurrent
                    el.types
                , includeUnknown
                )
        )
        ( Dict.empty, False )
        >> (\base ->
                case base of
                    ( d, True ) ->
                        Dict.insert unknownType True d

                    ( d, False ) ->
                        d
           )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ShowPage page ->
            updateModel { model | page = page }

        TypeEnabled typ enabled ->
            case model.page of
                CuesheetPage cuesModel ->
                    let
                        options =
                            cuesModel.waypointOptions

                        newCuesModel =
                            { cuesModel | waypointOptions = { options | filteredLocationTypes = Dict.insert typ enabled cuesModel.waypointOptions.filteredLocationTypes } }
                    in
                    updateCuesModel model newCuesModel

                _ ->
                    ( model, Cmd.none )

        ShowOptions show ->
            updateModel { model | showOptions = show }

        UpdateTotalDistanceDisplay maybeSelection ->
            maybeSelection
                |> Maybe.map
                    (\selection ->
                        let
                            options =
                                model.cuesViewOptions
                        in
                        updateModel { model | cuesViewOptions = { options | totalDistanceDisplay = selection } }
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdateFilterEnabled enabled ->
            case model.page of
                CuesheetPage cuesModel ->
                    let
                        options =
                            cuesModel.waypointOptions

                        newCuesModel =
                            { cuesModel | waypointOptions = { options | locationFilterEnabled = enabled } }
                    in
                    updateCuesModel model newCuesModel

                _ ->
                    ( model, Cmd.none )

        UpdatePosition position ->
            let
                options =
                    model.cuesViewOptions
            in
            updateModel { model | cuesViewOptions = { options | position = position } }

        UpdateReferencePoint point ->
            let
                options =
                    model.cuesViewOptions
            in
            updateModel { model | cuesViewOptions = { options | referencePoint = point } }

        UpdateItemSpacing spacing ->
            let
                options =
                    model.cuesViewOptions
            in
            updateModel { model | cuesViewOptions = { options | itemSpacing = spacing } }

        UpdateDistanceDetail detail ->
            let
                options =
                    model.cuesViewOptions
            in
            updateModel { model | cuesViewOptions = { options | distanceDetail = detail } }

        OpenFileBrowser ->
            ( model, File.Select.file [ "application/gpx+xml" ] FileUploaded )

        FileUploaded file ->
            ( { model | gpxError = Maybe.Nothing }
            , GpxApi.getElevationProfileDataResponse GpxResponseReceived (Maybe.withDefault "https://gpx.fly.dev" model.gpxServerURLOverride) file
            )

        GpxResponseReceived result ->
            case result of
                Err errMsg ->
                    ( { model | gpxError = Maybe.Just errMsg }, Cmd.none )

                Ok tracks ->
                    case tracks of
                        [ track ] ->
                            let
                                waypoints =
                                    track.waypoints
                                        |> List.map (\w -> Waypoint w.name w.distance w.categories)
                                        |> List.sortBy .distance
                            in
                            { model | page = CuesheetPage <| initialCuesModel waypoints, gpxError = Maybe.Nothing } |> updateModel

                        [] ->
                            ( { model | gpxError = Maybe.Just "No tracks found in GPX file" }, Cmd.none )

                        _ ->
                            ( { model | gpxError = Maybe.Just "Multiple tracks found in GPX file; only single-track GPX files are supported" }, Cmd.none )

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


updateCuesModel : Model -> CuesModel -> ( Model, Cmd Msg )
updateCuesModel model cuesModel =
    updateModel <| { model | page = CuesheetPage cuesModel }


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    let
        localStoredState =
            encodeSavedState longFieldNames model
    in
    ( model, storeState localStoredState )


initialCuesModel : List Waypoint -> CuesModel
initialCuesModel waypoints =
    let
        sortedWaypoint =
            List.sortBy .distance waypoints
    in
    CuesModel sortedWaypoint (initialWaypointOptions sortedWaypoint)



-- VIEW


view : Model -> Browser.Document Msg
view model =
    -- TODO: better title plz
    Browser.Document "Cuesheet"
        [ case model.page of
            CuesheetPage cuesheetModel ->
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
                                                    [ QRCode.toSvg [ Svg.Attributes.width "100%", Svg.Attributes.height "500" ] qr
                                                    , Html.br [] []
                                                    , Html.p [] [ Html.text "Scan the QR code above on your device" ]
                                                    , Html.p [] [ Html.text "and follow the link to load in the current cues." ]
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

                                                        QRCode.LogTableException _ ->
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
                        [ viewOptions model.showOptions
                            (List.head (List.reverse cuesheetModel.waypoints) |> Maybe.map .distance)
                            cuesheetModel.waypointOptions
                            model.cuesViewOptions
                            model.gpxError
                        , Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.class "wide"
                            , Html.Attributes.style "height" "100%"
                            , Html.Attributes.style "justify-content" "center"
                            ]
                            [ cuesheet (cues cuesheetModel.waypointOptions cuesheetModel.waypoints) model.cuesViewOptions
                            ]
                        ]

            WelcomePage val ->
                welcomePage val

            GetStartedPage ->
                getStartedPage model.gpxError
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

        waterType =
            "WATER"

        exampleWaypoints =
            [ Waypoint "Start" 0.0 []
            , Waypoint "Blue shoes" 56.1 [ cafeType ]
            , Waypoint "Lungburner" 56.3 [ climbType ]
            , Waypoint "Steep Street" 63.7 [ climbType ]
            , Waypoint "Foosville fountain" 98.3 [ waterType, cafeType ]
            , Waypoint "Cosy hedge" 198.2 [ "😴" ]
            , Waypoint "Legburner" 243.8 [ climbType ]
            , Waypoint "Finish" 273.5 []
            ]
    in
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "flex-center"
        , Html.Attributes.class "column"
        ]
        (List.concat
            [ [ Html.h2 [] [ Html.text "Cuesheet builder" ]
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
                    (List.map (\( desc, waypointModifier, opts ) -> Html.div [] [ Html.h4 [ Html.Attributes.style "text-align" "center" ] [ Html.text desc ], cuesheet (waypointModifier exampleWaypoints) opts ])
                        [ if toGo then
                            ( "Distance to go", identity, CuesViewOptions ToLast 1000 0 defaultSpacing defaultDistanceDetail )

                          else
                            ( "Distance from zero", identity, CuesViewOptions FromZero 1000 0 defaultSpacing defaultDistanceDetail )
                        , ( "Custom location types"
                          , List.map
                                (\w ->
                                    { w
                                        | types =
                                            List.map
                                                (\typ ->
                                                    Dict.get typ (Dict.fromList [ ( cafeType, "☕" ), ( climbType, "⛰️" ), ( waterType, "🚰" ) ])
                                                        |> Maybe.withDefault typ
                                                )
                                                w.types
                                    }
                                )
                          , CuesViewOptions None 1000 0 defaultSpacing defaultDistanceDetail
                          )
                        , ( "Custom spacing", identity, CuesViewOptions None 1000 0 (defaultSpacing - 10) defaultDistanceDetail )
                        , ( "Filter location types", cues (WaypointsOptions True (initialFilteredLocations exampleWaypoints |> Dict.map (\typ _ -> List.member typ [ unknownType, climbType, waterType ]))), CuesViewOptions None 1000 0 defaultSpacing defaultDistanceDetail )
                        ]
                    )
              ]
            ]
        )


getStartedPage : Maybe String -> Html Msg
getStartedPage gpxError =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "flex-center"
        , Html.Attributes.class "column"
        ]
        (List.concat
            [ [ Html.h2 [] [ Html.text "Cuesheet builder" ]
              , Html.br [] []
              , Html.h3 [] [ Html.text "Instructions" ]
              , Html.br [] []
              , Html.p [] [ Html.text "To make your cuesheet," ]
              , Html.p [] [ Html.text "upload a GPX file containing waypoints." ]
              , Html.p [] [ Html.text "Waypoints from the GPX will be used as cue points." ]
              , Html.br [] []
              , viewButton "upload GPX" OpenFileBrowser
              ]
            , gpxError |> Maybe.map (\err -> [ Html.br [] [], viewGpxErrorPanel err ]) |> Maybe.withDefault []
            , [ Html.br [] []
              , Html.br [] []
              ]
            ]
        )


optionGroup : String -> List (Html Msg) -> Html Msg
optionGroup title elements =
    Html.div [ Html.Attributes.class "flex-container", Html.Attributes.class "column" ]
        (Html.legend [] [ Html.text title ] :: elements)


viewOptions : Bool -> Maybe Float -> WaypointsOptions -> CuesViewOptions -> Maybe String -> Html Msg
viewOptions show maxDistance waypointOptions cuesViewOptions gpxError =
    Html.div
        [ Html.Attributes.class "flex-container"
        , Html.Attributes.class "column"
        , Html.Attributes.style "justify-content" "center"
        , Html.Attributes.style "overflow" "auto"
        , Html.Attributes.class "narrow"
        ]
        (if not show then
            [ Html.p
                [ Html.Attributes.style "transform" "rotate(90deg)"
                , Html.Attributes.style "white-space" "nowrap"
                , Html.Attributes.style "width" "1em"
                ]
                [ Html.span [ Html.Events.onClick <| ShowOptions True ] [ Html.text "options" ]
                , Html.span [] [ Html.text " | " ]
                , Html.span [ Html.Events.onClick <| ShowQR ] [ Html.text "share" ]
                ]
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
                                                    UpdateFilterEnabled False

                                                "filtered" ->
                                                    UpdateFilterEnabled True

                                                _ ->
                                                    Never
                                        )
                                        >> Maybe.withDefault Never
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
                                                            (if typ /= unknownType then
                                                                typ

                                                             else
                                                                "unknown"
                                                            )
                                                    )
                                             --        TODO(glynternet): add 'clear' and 'all' buttons
                                            )
                                        ]

                                    else
                                        []
                                   )
                            )
                        , Html.hr [] []
                        , optionGroup "Total distance"
                            ([ Dropdown.dropdown
                                (Dropdown.Options
                                    [ Dropdown.Item (formatTotalDistanceDisplay FromZero) (formatTotalDistanceDisplay FromZero) True
                                    , Dropdown.Item (formatTotalDistanceDisplay ToLast) (formatTotalDistanceDisplay ToLast) True
                                    , Dropdown.Item (formatTotalDistanceDisplay ToPoint) (formatTotalDistanceDisplay ToPoint) True
                                    , Dropdown.Item (formatTotalDistanceDisplay None) (formatTotalDistanceDisplay None) True
                                    ]
                                    Maybe.Nothing
                                    (Maybe.map (parseTotalDistanceDisplay Maybe.Nothing)
                                        >> Maybe.withDefault Maybe.Nothing
                                        >> UpdateTotalDistanceDisplay
                                    )
                                )
                                []
                                (Maybe.Just <| formatTotalDistanceDisplay cuesViewOptions.totalDistanceDisplay)
                             ]
                                ++ (case cuesViewOptions.totalDistanceDisplay of
                                        ToPoint ->
                                            [ Html.p []
                                                [ Html.input
                                                    [ Html.Attributes.type_ "number"
                                                    , Html.Attributes.min "0"
                                                    , maxDistance |> Maybe.map (String.fromFloat >> Html.Attributes.max) |> Maybe.withDefault (Html.Attributes.disabled True)
                                                    , Html.Attributes.value <| String.fromFloat cuesViewOptions.referencePoint
                                                    , Html.Events.onInput (String.toFloat >> Maybe.withDefault 1000 >> UpdateReferencePoint)
                                                    ]
                                                    []
                                                ]
                                            ]

                                        _ ->
                                            []
                                   )
                            )
                        , Html.hr [] []
                        , optionGroup "Position"
                            [ Html.input
                                [ Html.Attributes.type_ "range"
                                , Html.Attributes.min "0"
                                , maxDistance |> Maybe.map (String.fromFloat >> Html.Attributes.max) |> Maybe.withDefault (Html.Attributes.disabled True)
                                , Html.Attributes.value <| String.fromFloat cuesViewOptions.position
                                , Html.Events.onInput (String.toFloat >> Maybe.withDefault 0.0 >> UpdatePosition)
                                ]
                                []
                            ]
                        , optionGroup "Spacing"
                            [ Html.input
                                [ Html.Attributes.type_ "range"
                                , Html.Attributes.min "1"
                                , Html.Attributes.max "50"
                                , Html.Attributes.value <| String.fromInt cuesViewOptions.itemSpacing
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
                                , Html.Attributes.value <| String.fromInt cuesViewOptions.distanceDetail
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
                            [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "upload GPX" OpenFileBrowser
                            , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "clear" (ShowPage <| WelcomePage False)
                            , viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "share / send to device" ShowQR
                            ]
                        ]
                  ]
                , gpxError |> Maybe.map (\err -> [ Html.br [] [], viewGpxErrorPanel err ]) |> Maybe.withDefault [ Html.div [] [] ]
                ]
        )


viewGpxErrorPanel : String -> Html Msg
viewGpxErrorPanel error =
    viewErrorPanel <| ("There was an error processing your GPX file. Please fix any error and try again 😇\n\nError: " ++ String.left 1000 error)


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


parseTotalDistanceDisplay : Maybe Float -> String -> Maybe TotalDistanceDisplay
parseTotalDistanceDisplay point v =
    case v of
        "from zero" ->
            Maybe.Just FromZero

        "to last" ->
            Maybe.Just ToLast

        "to point" ->
            Maybe.Just <| ToPoint

        "hide" ->
            Maybe.Just None

        _ ->
            Maybe.Nothing


formatTotalDistanceDisplay : TotalDistanceDisplay -> String
formatTotalDistanceDisplay v =
    case v of
        FromZero ->
            "from zero"

        ToLast ->
            "to last"

        ToPoint ->
            "to point"

        None ->
            "hide"


cues : WaypointsOptions -> List Waypoint -> List Waypoint
cues waypointOptions waypoints =
    if waypointOptions.locationFilterEnabled then
        List.filterMap
            (\w ->
                let
                    includeType =
                        \typ ->
                            Dict.get typ waypointOptions.filteredLocationTypes
                                |> Maybe.withDefault True
                in
                case w.types of
                    -- if no types then we just check the unknown type key
                    [] ->
                        if includeType unknownType then
                            Maybe.Just w

                        else
                            Maybe.Nothing

                    types ->
                        case List.filter includeType types of
                            -- If there are types and they are all filtered out, don't show waypoint
                            [] ->
                                Maybe.Nothing

                            some ->
                                Maybe.Just { w | types = some }
            )
            waypoints

    else
        waypoints


cuesheet : List Waypoint -> CuesViewOptions -> Html Msg
cuesheet waypoints cuesViewOptions =
    let
        info =
            waypointInfos cuesViewOptions.position waypoints

        svgHeight =
            (*) cuesViewOptions.itemSpacing (List.length info)

        svgContentLeftStart =
            0

        svgContentLeftStartString =
            String.fromInt svgContentLeftStart

        lastWaypointDistance =
            List.head (List.reverse waypoints) |> Maybe.map .distance
    in
    Html.div
        [ Html.Attributes.class "cuesheet"
        ]
        [ Svg.svg
            [ Svg.Attributes.width "100%"
            , Svg.Attributes.height <| String.fromInt svgHeight
            , Svg.Attributes.viewBox <| "-40 -10 240 " ++ String.fromInt (svgHeight + cuesViewOptions.itemSpacing)
            ]
            -- TODO(glynternet): handle when no waypoints present after filtering
            (info
                |> List.indexedMap
                    (\i item ->
                        let
                            translate =
                                Svg.Attributes.transform <| "translate(0," ++ (String.fromInt <| i * cuesViewOptions.itemSpacing) ++ ")"
                        in
                        case item of
                            InfoWaypoint waypoint ->
                                let
                                    waypointDistance =
                                        case cuesViewOptions.totalDistanceDisplay of
                                            None ->
                                                Maybe.Nothing

                                            FromZero ->
                                                Maybe.Just (formatKm cuesViewOptions.distanceDetail waypoint.distance)

                                            ToLast ->
                                                lastWaypointDistance |> Maybe.map (\last -> formatKm cuesViewOptions.distanceDetail (last - waypoint.distance))

                                            ToPoint ->
                                                Maybe.Just (formatKm cuesViewOptions.distanceDetail (cuesViewOptions.referencePoint - waypoint.distance))

                                    waypointInfo =
                                        List.filterMap identity
                                            [ waypointDistance
                                            , case waypoint.types of
                                                [] ->
                                                    Maybe.Nothing

                                                types ->
                                                    Maybe.Just <| String.join ", " types
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
                                        , Svg.Attributes.y <| String.fromInt (cuesViewOptions.itemSpacing // 2)
                                        ]
                                        [ Svg.text waypoint.name ]
                                        :: (waypointInfoLines
                                                |> List.indexedMap
                                                    (\j line ->
                                                        Svg.text_
                                                            [ Svg.Attributes.x svgContentLeftStartString
                                                            , Svg.Attributes.y <| String.fromInt (cuesViewOptions.itemSpacing // 2)
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
                                        String.fromInt <| cuesViewOptions.itemSpacing - 2

                                    arrowHeadTop =
                                        String.fromInt <| cuesViewOptions.itemSpacing - 6

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
                                        , Svg.Attributes.y <| String.fromInt (cuesViewOptions.itemSpacing // 2)
                                        , Svg.Attributes.dominantBaseline "middle"
                                        , Svg.Attributes.fontSize "smaller"
                                        ]
                                        [ Svg.text <| formatKm cuesViewOptions.distanceDetail dist ]
                                    ]
                    )
            )
        ]


waypointInfos : Float -> List Waypoint -> List Info
waypointInfos position waypoints =
    List.foldl
        (\el accum ->
            if el.distance < position then
                accum

            else
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


formatKm : Int -> Float -> String
formatKm decimalPlaces metres =
    Round.round decimalPlaces (metres / 1000) ++ "km"


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
    , referencePoint : String
    , distanceDetail : String
    , locationFilterEnabled : String
    , filteredLocationTypes : String
    , itemSpacing : String
    , showOptions : String
    }


longFieldNames : StoredStateCodeFields
longFieldNames =
    { waypoints = "waypoints"
    , waypointName = "name"
    , waypointDistance = "distance"
    , waypointType = "typ"
    , totalDistanceDisplay = "totalDistanceDisplay"
    , referencePoint = "referencePoint"
    , distanceDetail = "distanceDetail"
    , locationFilterEnabled = "locationFilterEnabled"
    , filteredLocationTypes = "filteredLocationTypes"
    , itemSpacing = "itemSpacing"
    , showOptions = "showOptions"
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
    , referencePoint = "rp"
    , distanceDetail = "dd"
    , locationFilterEnabled = "lfe"
    , filteredLocationTypes = "flt"
    , itemSpacing = "is"
    , showOptions = "so"
    }


encodeSavedState : StoredStateCodeFields -> Model -> String
encodeSavedState fieldNames model =
    Json.Encode.object
        ((case model.page of
            CuesheetPage cuesModel ->
                [ ( fieldNames.waypoints, encodeWaypoints fieldNames cuesModel.waypoints )
                , ( fieldNames.locationFilterEnabled, Json.Encode.bool cuesModel.waypointOptions.locationFilterEnabled )
                , ( fieldNames.filteredLocationTypes, Json.Encode.dict identity Json.Encode.bool cuesModel.waypointOptions.filteredLocationTypes )
                ]

            _ ->
                []
         )
            ++ [ ( fieldNames.totalDistanceDisplay, Json.Encode.string <| formatTotalDistanceDisplay model.cuesViewOptions.totalDistanceDisplay )
               , ( fieldNames.referencePoint, Json.Encode.float model.cuesViewOptions.referencePoint )
               , ( fieldNames.distanceDetail, Json.Encode.int model.cuesViewOptions.distanceDetail )
               , ( fieldNames.itemSpacing, Json.Encode.int model.cuesViewOptions.itemSpacing )
               , ( fieldNames.showOptions, Json.Encode.bool model.showOptions )
               ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : StoredStateCodeFields -> Json.Decode.Decoder StoredState
storedStateDecoder fieldNames =
    Json.Decode.map8 StoredState
        (Json.Decode.maybe (Json.Decode.field fieldNames.waypoints (decodeWaypoints fieldNames)))
        (Json.Decode.maybe (Json.Decode.field fieldNames.totalDistanceDisplay Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field fieldNames.referencePoint Json.Decode.float))
        (Json.Decode.maybe (Json.Decode.field fieldNames.locationFilterEnabled Json.Decode.bool))
        (Json.Decode.maybe (Json.Decode.field fieldNames.filteredLocationTypes (Json.Decode.dict Json.Decode.bool)))
        (Json.Decode.maybe (Json.Decode.field fieldNames.itemSpacing Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field fieldNames.distanceDetail Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field fieldNames.showOptions Json.Decode.bool))


decodeWaypoints : StoredStateCodeFields -> Json.Decode.Decoder (List Waypoint)
decodeWaypoints fieldNames =
    Json.Decode.list
        (Json.Decode.map3 Waypoint
            (Json.Decode.field fieldNames.waypointName Json.Decode.string)
            (Json.Decode.field fieldNames.waypointDistance Json.Decode.float)
            (Json.Decode.field fieldNames.waypointType (Json.Decode.list Json.Decode.string))
        )


encodeWaypoints : StoredStateCodeFields -> List Waypoint -> Json.Encode.Value
encodeWaypoints fieldNames waypoints =
    Json.Encode.list
        (\waypoint ->
            Json.Encode.object
                [ ( fieldNames.waypointName, Json.Encode.string waypoint.name )
                , ( fieldNames.waypointDistance, Json.Encode.float waypoint.distance )
                , ( fieldNames.waypointType, Json.Encode.list Json.Encode.string waypoint.types )
                ]
        )
        waypoints


port storeState : String -> Cmd msg
