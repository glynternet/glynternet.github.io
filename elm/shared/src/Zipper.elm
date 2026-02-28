module Zipper exposing
    ( Zipper
    , decoder
    , encode
    , fromList
    , navigateNext
    , navigatePrevious
    , updateCurrent
    )

import Json.Decode
import Json.Encode


type alias Zipper a =
    { prev : List a
    , current : a
    , next : List a
    }


fromList : List a -> Maybe (Zipper a)
fromList elements =
    case elements of
        first :: rest ->
            Just (Zipper [] first rest)

        [] ->
            Nothing


navigatePrevious : Zipper a -> Zipper a
navigatePrevious zipper =
    case zipper.prev of
        [] ->
            zipper

        first :: rest ->
            Zipper rest first (zipper.current :: zipper.next)


navigateNext : Zipper a -> Zipper a
navigateNext zipper =
    case zipper.next of
        [] ->
            zipper

        first :: rest ->
            Zipper (zipper.current :: zipper.prev) first rest


updateCurrent : (a -> a) -> Zipper a -> Zipper a
updateCurrent update zipper =
    Zipper zipper.prev (update zipper.current) zipper.next



-- ENCODE/DECODE


encode : (a -> Json.Encode.Value) -> Zipper a -> Json.Encode.Value
encode encodeElement zipper =
    Json.Encode.object
        [ ( "previous", Json.Encode.list encodeElement zipper.prev )
        , ( "current", encodeElement zipper.current )
        , ( "next", Json.Encode.list encodeElement zipper.next )
        ]


decoder : Json.Decode.Decoder a -> Json.Decode.Decoder (Zipper a)
decoder elementDecoder =
    Json.Decode.map3 Zipper
        (Json.Decode.field "previous" (Json.Decode.list elementDecoder))
        (Json.Decode.field "current" elementDecoder)
        (Json.Decode.field "next" (Json.Decode.list elementDecoder))
