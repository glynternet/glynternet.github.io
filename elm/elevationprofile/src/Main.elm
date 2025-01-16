port module Main exposing (storeState)

import Browser
import Browser.Navigation
import File exposing (File)
import File.Select
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Events
import Http
import Json.Decode
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
        , onUrlRequest = \_ -> Ignore
        , onUrlChange = \_ -> Ignore
        }



-- MODEL


type alias Model =
    { profileData : LoadableResource ElevationProfileData
    , showOptions : Bool
    , gpxServerURLOverride : Maybe String
    }


type alias ElevationProfileData =
    List ElevationPoint


type alias ElevationPoint =
    { distance : Float
    , elevation : Float
    }


type alias StoredState =
    { file : Maybe String
    , profileData : Maybe ElevationProfileData
    , gpxServerURL : Maybe String
    }


storedStateModel : StoredState -> Model
storedStateModel state =
    Model (loadableResourceFromMaybe state.profileData) True state.gpxServerURL


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState
        |> Maybe.map
            (Json.Decode.decodeValue storedStateDecoder
                -- TODO: handle error
                >> Result.withDefault (StoredState Nothing Nothing Nothing)
                >> storedStateModel
            )
        |> Maybe.withDefault (Model NotLoaded True Nothing)
    , Cmd.none
    )


type Msg
    = Ignore
    | ShowOptions Bool
    | OpenFileBrowser
    | FileUploaded File.File
    | ElevationProfileDataResponse (Result String ElevationProfileData)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ShowOptions show ->
            ( { model | showOptions = show }, Cmd.none )

        OpenFileBrowser ->
            ( model, File.Select.file [ "application/gpx+xml" ] FileUploaded )

        FileUploaded file ->
            updateModel { model | profileData = Loading }
                |> Tuple.mapSecond
                    (\cmd ->
                        Cmd.batch
                            [ cmd
                            , Http.post
                                { url = Maybe.withDefault "https://gpx.fly.dev" model.gpxServerURLOverride
                                , body = Http.fileBody file
                                , expect =
                                    Http.expectJson
                                        (Result.mapError httpErrorString >> ElevationProfileDataResponse)
                                        decodeElevationProfile
                                }
                            ]
                    )

        ElevationProfileDataResponse resp ->
            updateModel { model | profileData = (loadableResourceFromResult << Result.mapError ((++) "getting profile data from GPX: ")) resp }

        Ignore ->
            ( model, Cmd.none )


updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    let
        localStoredState =
            encodeSavedState model
    in
    ( model, storeState localStoredState )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    Browser.Document "Elevation profile"
        [ Html.div
            [ Html.Attributes.class "flex-container"
            , Html.Attributes.class "row"
            , Html.Attributes.class "page"
            , Html.Attributes.style "height" "100%"
            ]
            [ viewOptions model.showOptions
            , Html.div
                [ Html.Attributes.class "flex-container"
                , Html.Attributes.class "column"
                , Html.Attributes.class "wide"
                , Html.Attributes.style "height" "100%"
                , Html.Attributes.style "justify-content" "center"
                ]
                [ case model.profileData of
                    NotLoaded ->
                        Html.p [] [ Html.text "Load your profile!" ]

                    Loading ->
                        Html.p [] [ Html.text "Loading profile..." ]

                    Error err ->
                        viewErrorPanel <| ("There was an error creating your profile. Please fix any error and try again 😇\n\nError: " ++ String.left 1000 err ++ "...")

                    Loaded profileData ->
                        profile profileData
                ]
            ]
        ]


viewOptions : Bool -> Html Msg
viewOptions show =
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
                        , Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.style "justify-content" "center"
                            , Html.Attributes.style "align-items" "center"
                            ]
                            [ viewButtonWithAttributes [ Html.Attributes.style "width" "100%" ] "upload GPX" OpenFileBrowser
                            ]
                        ]
                  ]
                ]
        )


viewErrorPanel : String -> Html Msg
viewErrorPanel error =
    Html.div [ Html.Attributes.class "error_panel" ] [ Html.text error ]


viewButtonWithAttributes : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButtonWithAttributes attrs text msg =
    Html.button
        ([ Html.Events.onClick msg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


profile : ElevationProfileData -> Html Msg
profile profileData =
    let
        -- TODO(ghanmer): combine these max folds to not iterate through twice
        maxElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.maximum <| List.map .elevation profileData

        minElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.minimum <| List.map .elevation profileData

        maxDistance =
            Maybe.withDefault 1 <| List.maximum <| List.map .distance profileData

        svgHeight =
            200

        svgWidth =
            500
    in
    Html.div
        [ Html.Attributes.class "TODO"
        ]
        [ Svg.svg
            [ Svg.Attributes.width "100%"
            , Svg.Attributes.height <| String.fromInt svgHeight

            --                          min-x min-y width height
            , Svg.Attributes.viewBox <| "0 0 " ++ String.fromInt svgWidth ++ " " ++ String.fromInt svgHeight
            ]
            ((profileData
                |> List.foldl
                    (accumulatePoints
                        (xyCalculator
                            { svgHeight = toFloat svgHeight
                            , svgWidth = toFloat svgWidth
                            , maxDistance = maxDistance
                            , minElevation = minElevation
                            , maxElevation = maxElevation
                            }
                        )
                    )
                    ( Nothing, [] )
                |> Tuple.second
             )
                ++ ([ ( ( 0, 0 ), ( svgHeight, 0 ) )
                    , ( ( 0, 0 ), ( 0, svgWidth ) )
                    , ( ( svgHeight, svgWidth ), ( svgHeight, 0 ) )
                    , ( ( svgHeight, svgWidth ), ( 0, svgWidth ) )
                    ]
                        |> List.map
                            (\( ( y1, x1 ), ( y2, x2 ) ) ->
                                Svg.line
                                    [ Svg.Attributes.x1 <| String.fromInt x1
                                    , Svg.Attributes.y1 <| String.fromInt y1
                                    , Svg.Attributes.x2 <| String.fromInt x2
                                    , Svg.Attributes.y2 <| String.fromInt y2
                                    , Svg.Attributes.stroke "grey"
                                    , Svg.Attributes.strokeWidth "1"
                                    ]
                                    []
                            )
                   )
            )
        ]


type alias XYCalculator =
    { x : Float -> String
    , y : Float -> String
    }


xyCalculator :
    { svgWidth : Float
    , svgHeight : Float
    , maxDistance : Float
    , minElevation : Float
    , maxElevation : Float
    }
    -> XYCalculator
xyCalculator cfg =
    let
        elevationRange =
            cfg.maxElevation - cfg.minElevation

        normaliseElevation =
            \elevation -> (elevation - cfg.minElevation) / elevationRange

        svgWidthPerDistanceUnit =
            cfg.svgWidth / cfg.maxDistance
    in
    XYCalculator
        (\distance ->
            String.fromFloat (distance * svgWidthPerDistanceUnit)
        )
        (\elevation ->
            String.fromFloat (cfg.svgHeight - cfg.svgHeight * normaliseElevation elevation)
        )



-- accumulatePoints takes in a config to form an accumulator.
-- The accumulator will take a point and form a tuple of (maybePrevPoint, currentLines), where each line in currentLines
-- is a formed Svg.Svg msg.
-- The maybePrevPoint is a Maybe (String, String) because the number values have been converted in a prior iteration of
-- the accumulation loop.


accumulatePoints : XYCalculator -> (ElevationPoint -> ( Maybe ( String, String ), List (Svg.Svg msg) ) -> ( Maybe ( String, String ), List (Svg.Svg msg) ))
accumulatePoints calc =
    \point ( maybePrevPoint, currLines ) ->
        let
            pointX =
                calc.x point.distance

            pointY =
                calc.y point.elevation
        in
        case maybePrevPoint of
            Nothing ->
                ( Just ( pointX, pointY ), [] )

            Just prev ->
                ( Just ( pointX, pointY )
                , Svg.line
                    [ Svg.Attributes.x1 <| Tuple.first prev
                    , Svg.Attributes.y1 <| Tuple.second prev
                    , Svg.Attributes.x2 <| pointX
                    , Svg.Attributes.y2 <| pointY
                    , Svg.Attributes.stroke "grey"
                    , Svg.Attributes.strokeWidth "1"
                    ]
                    []
                    :: currLines
                )


encodeElevationProfile : List ElevationPoint -> Json.Encode.Value
encodeElevationProfile points =
    Json.Encode.list
        (\point ->
            Json.Encode.object
                [ ( "dist", Json.Encode.float point.distance )
                , ( "ele", Json.Encode.float point.elevation )
                ]
        )
        points


decodeElevationProfile : Json.Decode.Decoder ElevationProfileData
decodeElevationProfile =
    Json.Decode.list
        (Json.Decode.map2 ElevationPoint
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "ele" Json.Decode.float)
        )



-- STATE


encodeSavedState : Model -> String
encodeSavedState model =
    Json.Encode.object
        (List.filterMap
            (\maybz -> maybz)
            [ case model.profileData of
                Loaded data ->
                    Just ( "profileData", encodeElevationProfile data )

                _ ->
                    Nothing
            , Maybe.map (\url -> ( "gpxServerURL", Json.Encode.string url )) model.gpxServerURLOverride
            ]
        )
        |> Json.Encode.encode 0


storedStateDecoder : Json.Decode.Decoder StoredState
storedStateDecoder =
    Json.Decode.map3 StoredState
        (Json.Decode.maybe (Json.Decode.field "file" Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field "profileData" decodeElevationProfile))
        (Json.Decode.maybe (Json.Decode.field "gpxServerURL" Json.Decode.string))


port storeState : String -> Cmd msg



-- PKG


type LoadableResource a
    = NotLoaded
    | Loading
    | Error String
    | Loaded a


loadableResourceFromMaybe : Maybe a -> LoadableResource a
loadableResourceFromMaybe =
    Maybe.map Loaded >> Maybe.withDefault NotLoaded


loadableResourceFromResult : Result String a -> LoadableResource a
loadableResourceFromResult =
    Result.map Loaded >> Result.mapError Error >> resultCollect


httpErrorString : Http.Error -> String
httpErrorString err =
    case err of
        Http.BadUrl msg ->
            "bad url: " ++ msg

        Http.Timeout ->
            "timeout"

        Http.NetworkError ->
            "network error"

        -- TODO(glynternet): can we capture the error message from the body?
        Http.BadStatus code ->
            "bad status: " ++ String.fromInt code

        Http.BadBody msg ->
            "bad body: " ++ msg


resultCollect : Result a a -> a
resultCollect res =
    case res of
        Ok a ->
            a

        Err a ->
            a
