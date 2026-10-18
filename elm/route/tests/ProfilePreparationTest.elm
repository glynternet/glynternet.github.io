module ProfilePreparationTest exposing (suite)

import Expect
import GpxApi
import ProfilePreparation
import Test exposing (Test, describe, test)


points : List GpxApi.TrackPoint
points =
    [ GpxApi.TrackPoint 0 100 51 -1 0 0
    , GpxApi.TrackPoint 1000 200 51.1 -1 100 0
    , GpxApi.TrackPoint 2000 150 51.2 -1 100 50
    ]


suite : Test
suite =
    describe "Transient profile preparation"
        [ test "elevation bounds cover the full route" <|
            \_ ->
                ProfilePreparation.prepare 1 Nothing points Nothing
                    |> (\prepared -> ( prepared.minElevation, prepared.maxElevation ))
                    |> Expect.equal ( 100, 200 )
        , test "intensity stays uncomputed while disabled" <|
            \_ -> ProfilePreparation.prepare 1 Nothing points Nothing |> .intensityPoints |> Expect.equal []
        , test "climbing intensity retains its existing exponential smoothing" <|
            \_ ->
                ProfilePreparation.prepare 1 (Just 1000) points Nothing
                    |> .intensityPoints
                    |> List.drop 1
                    |> List.head
                    |> Maybe.map .intensity
                    |> Maybe.withDefault -1
                    |> Expect.within (Expect.Absolute 0.0000001) (0.1 * (1 - e ^ -1))
        , test "descending decays intensity rather than adding negative climbing" <|
            \_ ->
                ProfilePreparation.prepare 1 (Just 1000) points Nothing
                    |> .intensityPoints
                    |> List.reverse
                    |> List.head
                    |> Maybe.map .intensity
                    |> Maybe.withDefault -1
                    |> Expect.within (Expect.Absolute 0.0000001) (0.1 * (1 - e ^ -1) * e ^ -1)
        , test "normalization includes the start of the whole route" <|
            \_ ->
                ProfilePreparation.prepare 1 (Just 1000) points Nothing
                    |> .minIntensity
                    |> Expect.within (Expect.Absolute 0.0000001) 0
        , test "the same revision and smoothing reuse the prepared values" <|
            \_ ->
                let
                    prepared =
                        ProfilePreparation.prepare 1 (Just 1000) points Nothing
                in
                ProfilePreparation.prepare 1 (Just 1000) points (Just prepared) |> Expect.equal prepared
        , test "hiding intensity keeps one result available for showing it again" <|
            \_ ->
                let
                    prepared =
                        ProfilePreparation.prepare 1 (Just 1000) points Nothing
                in
                ProfilePreparation.prepare 1 Nothing points (Just prepared)
                    |> Just
                    |> ProfilePreparation.prepare 1 (Just 1000) points
                    |> Expect.equal prepared
        , test "changing smoothing replaces intensity and retains source bounds" <|
            \_ ->
                ProfilePreparation.prepare 1 (Just 1000) points Nothing
                    |> Just
                    |> ProfilePreparation.prepare 1 (Just 2000) points
                    |> .intensityPoints
                    |> List.drop 1
                    |> List.head
                    |> Maybe.map .intensity
                    |> Maybe.withDefault -1
                    |> Expect.within (Expect.Absolute 0.0000001) (0.1 * (1 - e ^ -0.5))
        , test "a new source revision replaces old route bounds and intensity" <|
            \_ ->
                ProfilePreparation.prepare 1 (Just 1000) points Nothing
                    |> Just
                    |> ProfilePreparation.prepare 2 (Just 1000) [ GpxApi.TrackPoint 0 900 52 -2 0 0 ]
                    |> (\prepared -> ( prepared.sourceRevision, prepared.minElevation, prepared.intensityPoints ))
                    |> Expect.equal ( 2, 900, [ { distance = 0, intensity = 0 } ] )
        , test "changing the source while intensity is hidden drops the old intensity list" <|
            \_ ->
                ProfilePreparation.prepare 1 (Just 1000) points Nothing
                    |> Just
                    |> ProfilePreparation.prepare 2 Nothing [ GpxApi.TrackPoint 0 900 52 -2 0 0 ]
                    |> .intensityPoints
                    |> Expect.equal []
        , test "an empty source keeps the previous display fallback without old points" <|
            \_ ->
                ProfilePreparation.prepare 1 (Just 1000) points Nothing
                    |> Just
                    |> ProfilePreparation.prepare 2 (Just 1000) []
                    |> (\prepared -> ( prepared.minElevation, prepared.maxElevation, prepared.intensityPoints ))
                    |> Expect.equal ( 1, 1, [] )
        ]
