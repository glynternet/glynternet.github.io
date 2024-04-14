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


type alias StoredState =
    { file : Maybe String
    , profileData : Maybe ProfileData
    }


type alias Model =
    { file : Maybe String
    , page : Page
    , showOptions : Bool
    }


type Page
    = ProfilePage (LoadableResource ProfileData)


storedStateModel : StoredState -> Model
storedStateModel state =
    Model state.file (ProfilePage (loadableResourceFromMaybe state.profileData)) True


type alias Point =
    { distance : Float
    , elevation : Float
    }


type alias ProfileData =
    { points : List Point }


init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init maybeState _ _ =
    ( maybeState
        |> Maybe.map
            (Json.Decode.decodeValue storedStateDecoder
                -- TODO: handle error
                >> Result.withDefault (StoredState Nothing Nothing)
                >> storedStateModel
            )
        |> Maybe.withDefault (Model Nothing (ProfilePage NotLoaded) True)
    , Cmd.none
    )


type Msg
    = Ignore
    | ShowOptions Bool
    | OpenFileBrowser
    | FileUploaded File.File
      -- can probably streamline some of these steps
    | ProfileDataResponse (Result String ProfileData)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ShowOptions show ->
            ( { model | showOptions = show }, Cmd.none )

        OpenFileBrowser ->
            ( model, File.Select.file [ "application/gpx+xml" ] FileUploaded )

        FileUploaded file ->
            updateModel { model | page = ProfilePage Loading }
                |> Tuple.mapSecond
                    (\cmd ->
                        Cmd.batch
                            [ cmd
                            , Http.post
                                { url = "http://127.0.0.1:4001"
                                , body = Http.fileBody file
                                , expect =
                                    Http.expectJson
                                        -- TODO(glynternet): actually handle and bubble up this error
                                        (Result.mapError httpErrorString >> Result.map ProfileData >> ProfileDataResponse)
                                        decodeElevationProfile
                                }
                            ]
                    )

        ProfileDataResponse resp ->
            updateModel { model | page = ProfilePage <| loadableResourceFromResult resp }

        Ignore ->
            ( model, Cmd.none )


httpErrorString : Http.Error -> String
httpErrorString err =
    case err of
        Http.BadUrl msg ->
            "bad url: " ++ msg

        Http.Timeout ->
            "timeout"

        Http.NetworkError ->
            "network error"

        Http.BadStatus code ->
            "bad status: " ++ String.fromInt code

        Http.BadBody msg ->
            "bad body: " ++ msg


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
        [ case model.page of
            ProfilePage profileModel ->
                Html.div
                    [ Html.Attributes.class "flex-container"
                    , Html.Attributes.class "row"
                    , Html.Attributes.class "page"
                    , Html.Attributes.style "height" "100%"
                    ]
                    [ viewOptions model.showOptions
                        (case profileModel of
                            Error err ->
                                Just err

                            _ ->
                                Nothing
                        )
                    , Html.div
                        [ Html.Attributes.class "flex-container"
                        , Html.Attributes.class "column"
                        , Html.Attributes.class "wide"
                        , Html.Attributes.style "height" "100%"
                        , Html.Attributes.style "justify-content" "center"
                        ]
                        [ case model.page of
                            ProfilePage res ->
                                case res of
                                    NotLoaded ->
                                        Html.p [] [ Html.text "Load your profile!" ]

                                    Loading ->
                                        Html.p [] [ Html.text "Loading profile..." ]

                                    Error err ->
                                        Html.p [] [ Html.text <| "Error loading your profile: " ++ err ]

                                    Loaded profileData ->
                                        profile profileData
                        ]
                    ]
        ]


resultCollect : Result a a -> a
resultCollect res =
    case res of
        Ok a ->
            a

        Err a ->
            a


optionGroup : String -> List (Html Msg) -> Html Msg
optionGroup title elements =
    Html.div [ Html.Attributes.class "flex-container", Html.Attributes.class "column" ]
        (Html.legend [] [ Html.text title ] :: elements)



-- TODO(glynternet): move the decode error out of the view options?


viewOptions : Bool -> Maybe String -> Html Msg
viewOptions show decodeError =
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
                , decodeError |> Maybe.map (\err -> [ Html.br [] [], viewCSVDecodeErrorPanel err ]) |> Maybe.withDefault [ Html.div [] [] ]
                ]
        )


viewCSVDecodeErrorPanel : String -> Html Msg
viewCSVDecodeErrorPanel error =
    viewErrorPanel <| ("There was an error decoding your CSV. Please fix any error and try again 😇\n\nThe first few errors can be seen below.\n\n" ++ String.left 1000 error ++ "...")


viewErrorPanel : String -> Html Msg
viewErrorPanel error =
    Html.div [ Html.Attributes.class "error_panel" ] [ Html.text error ]


viewButtonWithAttributes : List (Html.Attribute Msg) -> String -> Msg -> Html Msg
viewButtonWithAttributes attrs text msg =
    Html.button
        ([ Html.Events.onClick msg, Html.Attributes.class "button-4", Html.Attributes.style "max-width" "20em" ] ++ attrs)
        [ Html.text text ]


profile : ProfileData -> Html Msg
profile data =
    let
        -- TODO(ghanmer): combine these max folds to not iterate through twice
        maxElevation =
            -- TODO(ghanmer): handle empty list etc better, although this is probably fine
            Maybe.withDefault 1 <| List.maximum <| List.map .elevation data.points

        maxDistance =
            Maybe.withDefault 1 <| List.maximum <| List.map .distance data.points

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
            ((data.points
                |> List.foldl
                    (accumulatePoints
                        { svgHeight = toFloat svgHeight
                        , svgWidth = toFloat svgWidth
                        , maxElevation = maxElevation
                        , maxDistance = maxDistance
                        }
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


accumulatePoints :
    { svgWidth : Float
    , svgHeight : Float
    , maxDistance : Float
    , maxElevation : Float
    }
    -> (Point -> ( Maybe ( String, String ), List (Svg.Svg msg) ) -> ( Maybe ( String, String ), List (Svg.Svg msg) ))
accumulatePoints cfg =
    \point ( maybePrevPoint, currLines ) ->
        let
            pointX =
                String.fromFloat (cfg.svgWidth * point.distance / cfg.maxDistance)

            pointY =
                String.fromFloat (cfg.svgHeight - cfg.svgHeight * point.elevation / cfg.maxElevation)
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


encodeElevationProfile : List Point -> Json.Encode.Value
encodeElevationProfile points =
    Json.Encode.list
        (\point ->
            Json.Encode.object
                [ ( "dist", Json.Encode.float point.distance )
                , ( "ele", Json.Encode.float point.elevation )
                ]
        )
        points


decodeElevationProfile : Json.Decode.Decoder (List Point)
decodeElevationProfile =
    Json.Decode.list
        (Json.Decode.map2 Point
            (Json.Decode.field "dist" Json.Decode.float)
            (Json.Decode.field "ele" Json.Decode.float)
        )



-- STATE
-- The field names in these encoded JSON objects must match exactly the field names
-- in the records of the Model to ensure that deserialising works as expected.


encodeSavedState : Model -> String
encodeSavedState model =
    Json.Encode.object
        ((case model.file of
            Just file ->
                [ ( "file", Json.Encode.string file ) ]

            Nothing ->
                []
         )
            ++ (case model.page of
                    ProfilePage profilePage ->
                        case profilePage of
                            NotLoaded ->
                                []

                            Loading ->
                                []

                            Error _ ->
                                []

                            Loaded data ->
                                [ ( "profileData", encodeElevationProfile data.points ) ]
               )
        )
        |> Json.Encode.encode 0


storedStateDecoder : Json.Decode.Decoder StoredState
storedStateDecoder =
    Json.Decode.map2 StoredState
        (Json.Decode.maybe (Json.Decode.field "file" Json.Decode.string))
        (Json.Decode.maybe (Json.Decode.field "profileData" (Json.Decode.map ProfileData decodeElevationProfile)))


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
