port module Main exposing (storeState)

import Browser
import Browser.Navigation
import File
import File.Select
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Events
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


type alias StoredState =    {    }


type alias Model =
    { page : Page
    , showOptions : Bool
    , url : Url.Url
    }


type Page
    = ProfilePage ProfileModel


type alias ProfileModel =
    { decodeError : Maybe String }



init : Maybe Json.Decode.Value -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ url _ =
    (Model (ProfilePage (ProfileModel Nothing)) True  url,Cmd.none)

type Msg
    = Ignore
    | ShowPage Page
    | ShowOptions Bool
    | OpenFileBrowser
    | FileUploaded File.File



update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ShowPage page ->
            updateModel { model | page = page }

        ShowOptions show ->
            ( { model | showOptions = show }, Cmd.none )

        OpenFileBrowser ->
            ( model, File.Select.file [ "text/csv" ] FileUploaded )

        FileUploaded file ->
            ( model
            --, File.toString file
            --    |> Task.map decodeCSV
            --    |> Task.perform GPXUploaded
            , Cmd.none
            )

        Ignore ->
            ( model, Cmd.none )



updateModel : Model -> ( Model, Cmd Msg )
updateModel model =
    let
        localStoredState =
            encodeSavedState longFieldNames model
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
                        [ viewOptions model.showOptions profileModel.decodeError
                        , Html.div
                            [ Html.Attributes.class "flex-container"
                            , Html.Attributes.class "column"
                            , Html.Attributes.class "wide"
                            , Html.Attributes.style "height" "100%"
                            , Html.Attributes.style "justify-content" "center"
                            ]
                            [ profile
                            ]
                        ]

        ]






optionGroup : String -> List (Html Msg) -> Html Msg
optionGroup title elements =
    Html.div [ Html.Attributes.class "flex-container", Html.Attributes.class "column" ]
        (Html.legend [] [ Html.text title ] :: elements)


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
                        , optionGroup "Spacing"
                            [ Html.input
                                [ Html.Attributes.type_ "range"
                                , Html.Attributes.min "1"
                                , Html.Attributes.max "50"
                                , Html.Attributes.value <| String.fromInt 43
                                , Html.Events.onInput (String.toInt >> Maybe.withDefault 666 >> always Ignore)
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



profile : Html Msg
profile  =
    Html.div
        [ Html.Attributes.class "TODO"
        ]
        [ Svg.svg
            (let
                svgHeight = 50
            in
                [ Svg.Attributes.width "100%"
                , Svg.Attributes.height <| String.fromInt svgHeight
                , Svg.Attributes.viewBox <| "-120 -10 240 " ++ String.fromInt (svgHeight)
                ])
            []
        ]


-- STATE
-- The field names in these encoded JSON objects must match exactly the field names
-- in the records of the Model to ensure that deserialising works as expected.


type alias StoredStateCodeFields =
    {
    }


longFieldNames : StoredStateCodeFields
longFieldNames =
    { }


{-| shortFieldNames are used within the QR code to reduce the payload size,
as when the state is transferred as a query param it's easy to overload
the server used under the hood for jekyll and get the following error
which results in a 404:
ERROR WEBrick::HTTPStatus::RequestURITooLarge
-}
shortFieldNames : StoredStateCodeFields
shortFieldNames =
    {   }


encodeSavedState : StoredStateCodeFields -> Model -> String
encodeSavedState fieldNames model =
    Json.Encode.object
        ([ ])
        |> Json.Encode.encode 0


port storeState : String -> Cmd msg

