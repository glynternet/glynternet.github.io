module PaceTest exposing (suite)

import Expect
import Pace
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Pace"
        [ setSpeedTests
        , fromElapsedTests
        , fromRideStartTests
        , sourceTests
        ]


ride : { position : Maybe Float, now : Maybe Time.Posix, zone : Time.Zone }
ride =
    { position = Just 18000
    , now = Just (Time.millisToPosix 1787310000000) -- 2026-08-21T11:00:00Z
    , zone = Time.utc
    }


defaultOptions : Pace.Options ()
defaultOptions =
    Pace.defaultOptions () ()


elapsedOptions : Pace.Options ()
elapsedOptions =
    { defaultOptions | activePaceSource = Pace.FromElapsed, elapsedAtStartSec = 3600 }


rideStartOptions : Pace.Options ()
rideStartOptions =
    { defaultOptions | activePaceSource = Pace.FromRideStart, rideStart = "2026-08-21T08:00" }


setSpeedTests : Test
setSpeedTests =
    describe "set speed"
        [ test "converts km/h to metres per second" <|
            \_ ->
                Pace.metresPerSecond ride { defaultOptions | speedKmh = 18 }
                    |> expectMaybeFloat (Just 5)
        , test "does not require a position or clock" <|
            \_ ->
                Pace.metresPerSecond { ride | position = Nothing, now = Nothing } { defaultOptions | speedKmh = 18 }
                    |> expectMaybeFloat (Just 5)
        , test "zero speed yields no estimate" <|
            \_ -> Pace.metresPerSecond ride { defaultOptions | speedKmh = 0 } |> Expect.equal Nothing
        , test "negative speed yields no estimate" <|
            \_ -> Pace.metresPerSecond ride { defaultOptions | speedKmh = -18 } |> Expect.equal Nothing
        , test "a set speed does not imply an elapsed ride time" <|
            \_ ->
                Pace.elapsedSoFar ride { defaultOptions | elapsedAtStartSec = 3600, rideStart = "2026-08-21T08:00" }
                    |> Expect.equal Nothing
        ]


fromElapsedTests : Test
fromElapsedTests =
    describe "entered elapsed time"
        ([ test "averages distance covered over total elapsed time" <|
            \_ -> Pace.metresPerSecond ride elapsedOptions |> expectMaybeFloat (Just 5)
         , test "does not require a clock or a valid start datetime" <|
            \_ ->
                Pace.metresPerSecond { ride | now = Nothing } { elapsedOptions | rideStart = "junk" }
                    |> expectMaybeFloat (Just 5)
         , test "selected endpoints do not change the ride-so-far average" <|
            \_ ->
                Pace.metresPerSecond ride
                    { start = 10000
                    , end = 15000
                    , activePaceSource = Pace.FromElapsed
                    , speedKmh = 1
                    , elapsedAtStartSec = 3600
                    , rideStart = ""
                    }
                    |> expectMaybeFloat (Just 5)
         ]
            ++ List.map
                (\( label, position ) ->
                    test label <|
                        \_ -> Pace.metresPerSecond { ride | position = position } elapsedOptions |> Expect.equal Nothing
                )
                [ ( "no position yields no estimate", Nothing )
                , ( "the route start yields no estimate", Just 0 )
                , ( "a negative position yields no estimate", Just -100 )
                ]
            ++ List.map
                (\elapsed ->
                    test ("elapsed time of " ++ String.fromFloat elapsed ++ " yields no estimate") <|
                        \_ ->
                            Pace.metresPerSecond ride { elapsedOptions | elapsedAtStartSec = elapsed }
                                |> Expect.equal Nothing
                )
                [ 0, -3600 ]
        )


fromRideStartTests : Test
fromRideStartTests =
    describe "elapsed time from the start datetime"
        (List.map
            (\( label, start, elapsed ) ->
                test label <|
                    \_ ->
                        let
                            options =
                                { rideStartOptions | rideStart = start }
                        in
                        Expect.all
                            [ \_ -> Pace.elapsedSoFar ride options |> expectMaybeFloat (Just elapsed)
                            , \_ ->
                                Pace.metresPerSecond ride options
                                    |> expectMaybeFloat
                                        (if elapsed > 0 then
                                            Just (18000 / elapsed)

                                         else
                                            Nothing
                                        )
                            ]
                            ()
            )
            [ ( "same morning", "2026-08-21T08:00", 10800 )
            , ( "across midnight", "2026-08-20T22:00", 46800 )
            , ( "across several days", "2026-08-18T10:00", 262800 )
            , ( "across a year boundary", "2025-12-31T23:00", 20088000 )
            , ( "includes entered seconds", "2026-08-21T08:05:30", 10470 )
            , ( "no time has passed", "2026-08-21T11:00", 0 )
            , ( "a future start yields no speed", "2026-08-21T12:00", -3600 )
            ]
            ++ List.map
                (\start ->
                    test ("unparseable start: " ++ start) <|
                        \_ ->
                            let
                                options =
                                    { rideStartOptions | rideStart = start }
                            in
                            Expect.all
                                [ \_ -> Pace.elapsedSoFar ride options |> Expect.equal Nothing
                                , \_ -> Pace.metresPerSecond ride options |> Expect.equal Nothing
                                ]
                                ()
                )
                [ "", "2026-08", "junk" ]
            ++ [ test "no clock yields neither elapsed time nor speed" <|
                    \_ ->
                        Expect.all
                            [ \_ -> Pace.elapsedSoFar { ride | now = Nothing } rideStartOptions |> Expect.equal Nothing
                            , \_ -> Pace.metresPerSecond { ride | now = Nothing } rideStartOptions |> Expect.equal Nothing
                            ]
                            ()
               , test "the start datetime is read in the device's local zone" <|
                    \_ ->
                        Pace.elapsedSoFar { ride | zone = Time.customZone 120 [] }
                            { rideStartOptions | rideStart = "2026-08-21T11:00" }
                            |> expectMaybeFloat (Just 7200)
               , test "the average follows the clock as time passes" <|
                    \_ ->
                        Pace.metresPerSecond { ride | now = Just (Time.millisToPosix 1787313600000) } rideStartOptions
                            |> expectMaybeFloat (Just 1.25)
               , test "a valid clock and start still require a route position" <|
                    \_ -> Pace.metresPerSecond { ride | position = Nothing } rideStartOptions |> Expect.equal Nothing
               ]
        )


sourceTests : Test
sourceTests =
    describe "saved source names"
        (List.map
            (\( source, stored ) ->
                test ("preserves the stored value " ++ stored) <|
                    \_ ->
                        ( Pace.formatSource source, Pace.parseSource stored )
                            |> Expect.equal ( stored, Just source )
            )
            [ ( Pace.SetSpeed, "speed" )
            , ( Pace.FromElapsed, "elapsed" )
            , ( Pace.FromRideStart, "rideStart" )
            ]
            ++ [ test "an unknown source is left for the caller to default" <|
                    \_ -> Pace.parseSource "unknown" |> Expect.equal Nothing
               ]
        )


expectMaybeFloat : Maybe Float -> Maybe Float -> Expect.Expectation
expectMaybeFloat expected actual =
    case ( expected, actual ) of
        ( Just expectedValue, Just actualValue ) ->
            Expect.within (Expect.Absolute 0.000001) expectedValue actualValue

        _ ->
            Expect.equal expected actual
