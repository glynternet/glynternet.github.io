module RouteFilenameTest exposing (suite)

import Expect
import RouteFilename
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "RouteFilename"
        [ test "uses the uploaded GPX basename as the route name" <|
            \_ -> RouteFilename.fromUploadFilename "rides/alpine-tour.gpx" |> Expect.equal "alpine-tour"
        , test "sanitises names that could escape the download filename" <|
            \_ -> RouteFilename.filename "  Alpine: Tour?.gpx  " ".gpx" |> Expect.equal "Alpine- Tour-.gpx"
        , test "falls back when the route has no usable name" <|
            \_ -> RouteFilename.filename "..." ".json" |> Expect.equal "route.json"
        , test "keeps the output format as the extension" <|
            \_ -> RouteFilename.filename "alpine-tour" ".json" |> Expect.equal "alpine-tour.json"
        ]
