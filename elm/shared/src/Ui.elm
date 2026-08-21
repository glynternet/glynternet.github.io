module Ui exposing
    ( card
    , cardHeading
    , labelledControl
    , note
    , noticePanel
    , row
    , section
    )

{-| The small pieces the figure-reporting tabs are built from: a card, its heading, a titled
section of rows, a label-and-value row, an aside, and a notice standing in for figures that
could not be worked out.

Every one is `Html msg` rather than `Html Msg`, so nothing here has an opinion about what the
app's messages are — the two that take content take it from the caller, messages and all.

-}

import Html exposing (Html)
import Html.Attributes


{-| Stands in the place figures would have gone, saying what is missing.
-}
noticePanel : String -> Html msg
noticePanel text =
    Html.div [ Html.Attributes.class "warning_panel" ] [ Html.text text ]


labelledControl : String -> Html msg -> Html msg
labelledControl label control =
    Html.label
        [ Html.Attributes.style "display" "inline-flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.2em"
        ]
        [ Html.span
            [ Html.Attributes.style "font-size" "0.85em"
            , Html.Attributes.style "opacity" "0.7"
            ]
            [ Html.text label ]
        , control
        ]


card : Html msg -> List (Html msg) -> Html msg
card heading contents =
    Html.div
        [ Html.Attributes.style "border" "1px solid #ddd"
        , Html.Attributes.style "border-radius" "6px"
        , Html.Attributes.style "padding" "0.5em 0.75em"
        , Html.Attributes.style "background" "#fafafa"
        , Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.5em"
        ]
        (heading :: contents)


{-| A card's title row, laid out so a card with more to say than its title — a collapsed one
naming the point it holds, say — can put it on the same line.
-}
cardHeading : List (Html.Attribute msg) -> List (Html msg) -> Html msg
cardHeading attributes contents =
    Html.h3
        (Html.Attributes.style "margin" "0"
            :: Html.Attributes.style "display" "flex"
            :: Html.Attributes.style "flex-wrap" "wrap"
            :: Html.Attributes.style "gap" "0.4em"
            :: Html.Attributes.style "align-items" "baseline"
            :: attributes
        )
        contents


{-| A titled group of rows. The note says where the section's figures were measured from, and
is empty when there is nothing to disambiguate.
-}
section : String -> String -> List (Html msg) -> Html msg
section title sectionNote rows =
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-direction" "column"
        , Html.Attributes.style "gap" "0.15em"
        ]
        (Html.div
            [ Html.Attributes.style "font-size" "0.85em"
            , Html.Attributes.style "opacity" "0.7"
            , Html.Attributes.style "border-bottom" "1px solid #ddd"
            , Html.Attributes.style "display" "flex"
            , Html.Attributes.style "flex-wrap" "wrap"
            , Html.Attributes.style "gap" "0.5em"
            , Html.Attributes.style "justify-content" "space-between"
            ]
            [ Html.text title
            , Html.span [ Html.Attributes.style "font-style" "italic" ] [ Html.text sectionNote ]
            ]
            :: rows
        )


{-| An aside under a card's rows, for saying something about where the figures above it came
from rather than adding another figure of its own.
-}
note : String -> Html msg
note text =
    Html.div
        [ Html.Attributes.style "font-size" "0.85em"
        , Html.Attributes.style "opacity" "0.7"
        , Html.Attributes.style "font-style" "italic"
        ]
        [ Html.text text ]


row : String -> String -> Html msg
row label value =
    Html.div
        [ Html.Attributes.style "display" "flex"
        , Html.Attributes.style "flex-wrap" "wrap"
        , Html.Attributes.style "gap" "0.5em"
        , Html.Attributes.style "justify-content" "space-between"
        ]
        [ Html.span [ Html.Attributes.style "opacity" "0.7" ] [ Html.text label ]
        , Html.span [] [ Html.text value ]
        ]
