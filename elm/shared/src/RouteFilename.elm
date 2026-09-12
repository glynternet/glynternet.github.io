module RouteFilename exposing (fromUploadFilename, filename)

import Char
import String


fromUploadFilename : String -> String
fromUploadFilename uploadedFilename =
    let
        basename =
            uploadedFilename
                |> String.trim
                |> String.split "/"
                |> List.reverse
                |> List.head
                |> Maybe.withDefault ""

        withoutGpx =
            if String.endsWith ".gpx" (String.toLower basename) then
                String.dropRight 4 basename

            else
                basename
    in
    sanitise withoutGpx


filename : String -> String -> String
filename routeName extension =
    let
        safeName =
            sanitise routeName

        withoutExtension =
            if String.endsWith (String.toLower extension) (String.toLower safeName) then
                String.dropRight (String.length extension) safeName

            else
                safeName
    in
    (if String.isEmpty withoutExtension then
        "route"

     else
        withoutExtension
    )
        ++ extension


sanitise : String -> String
sanitise value =
    value
        |> String.trim
        |> String.split ""
        |> List.map
            (\character ->
                if invalidCharacter character then
                    "-"

                else
                    character
            )
        |> String.concat
        |> String.trim
        |> trimDots


invalidCharacter : String -> Bool
invalidCharacter character =
    case String.uncons character of
        Just (first, _) ->
            List.member first [ '<', '>', ':', '"', '/', '\\', '|', '?', '*' ] || Char.toCode first < 32

        Nothing ->
            False


trimDots : String -> String
trimDots value =
    if String.startsWith "." value then
        trimDots (String.dropLeft 1 value)

    else if String.endsWith "." value then
        trimDots (String.dropRight 1 value)

    else
        value
