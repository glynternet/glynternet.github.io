module WallclockTest exposing (suite)

import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, test)
import Time
import Wallclock


suite : Test
suite =
    describe "Wallclock"
        [ daysFromCivilTests
        , elapsedTests
        , parseLocalDateTimeTests
        , durationTests
        , timeOfDayAfterTests
        ]


{-| The calendar arithmetic everything else rests on, and the one part of the module that could
be quietly wrong for years without ever looking wrong.
-}
daysFromCivilTests : Test
daysFromCivilTests =
    describe "daysFromCivil"
        [ test "the epoch is day zero" <|
            \_ -> Wallclock.daysFromCivil 1970 1 1 |> Expect.equal 0
        , test "the day before the epoch is day minus one" <|
            \_ -> Wallclock.daysFromCivil 1969 12 31 |> Expect.equal -1
        , test "counts a plain year" <|
            \_ -> Wallclock.daysFromCivil 1971 1 1 |> Expect.equal 365
        , test "counts a leap year" <|
            \_ -> Wallclock.daysFromCivil 1973 1 1 |> Expect.equal (365 * 2 + 366)
        , test "2000 was a leap year (the 400 rule)" <|
            \_ ->
                Wallclock.daysFromCivil 2000 3 1
                    - Wallclock.daysFromCivil 2000 2 28
                    |> Expect.equal 2
        , test "1900 was not a leap year (the 100 rule)" <|
            \_ ->
                Wallclock.daysFromCivil 1900 3 1
                    - Wallclock.daysFromCivil 1900 2 28
                    |> Expect.equal 1
        , test "2026 is not a leap year" <|
            \_ ->
                Wallclock.daysFromCivil 2026 3 1
                    - Wallclock.daysFromCivil 2026 2 28
                    |> Expect.equal 1
        , fuzz (Fuzz.intRange 1900 2200) "every year runs 365 or 366 days" <|
            \year ->
                Wallclock.daysFromCivil (year + 1) 1 1
                    - Wallclock.daysFromCivil year 1 1
                    |> Expect.all [ Expect.atLeast 365, Expect.atMost 366 ]
        , fuzz (Fuzz.intRange 1900 2200) "every month is a real month long" <|
            \year ->
                List.range 1 11
                    |> List.map (\month -> Wallclock.daysFromCivil year (month + 1) 1 - Wallclock.daysFromCivil year month 1)
                    |> Expect.all
                        [ List.minimum >> Maybe.withDefault 0 >> Expect.all [ Expect.atLeast 28, Expect.atMost 29 ]
                        , List.maximum >> Expect.equal (Just 31)
                        ]
        ]


{-| The differences the Pace tab actually asks for, spelled out as hours.
-}
elapsedTests : Test
elapsedTests =
    let
        hoursBetween from to =
            case ( Wallclock.parseLocalDateTime from, Wallclock.parseLocalDateTime to ) of
                ( Just a, Just b ) ->
                    toFloat (Wallclock.civilSeconds b - Wallclock.civilSeconds a) / 3600

                _ ->
                    -1
    in
    describe "civilSeconds differences"
        [ test "the same morning" <|
            \_ -> hoursBetween "2026-08-21T08:00" "2026-08-21T11:00" |> Expect.within (Expect.Absolute 0.001) 3
        , test "across midnight" <|
            \_ -> hoursBetween "2026-08-20T22:00" "2026-08-21T11:00" |> Expect.within (Expect.Absolute 0.001) 13
        , test "across several days" <|
            \_ -> hoursBetween "2026-08-18T10:00" "2026-08-21T11:00" |> Expect.within (Expect.Absolute 0.001) 73
        , test "across a year boundary" <|
            \_ -> hoursBetween "2025-12-31T23:00" "2026-08-21T11:00" |> Expect.within (Expect.Absolute 0.001) 5580
        , test "across a leap day" <|
            \_ -> hoursBetween "2024-02-28T12:00" "2024-03-01T12:00" |> Expect.within (Expect.Absolute 0.001) 48
        , test "a start in the future is negative" <|
            \_ -> hoursBetween "2026-08-22T08:00" "2026-08-21T11:00" |> Expect.lessThan 0
        ]


parseLocalDateTimeTests : Test
parseLocalDateTimeTests =
    describe "parseLocalDateTime"
        [ test "reads what a datetime-local input holds" <|
            \_ ->
                Wallclock.parseLocalDateTime "2026-08-21T08:05"
                    |> Expect.equal (Just { year = 2026, month = 8, day = 21, hour = 8, minute = 5, second = 0 })
        , test "reads seconds when the input includes them" <|
            \_ ->
                Wallclock.parseLocalDateTime "2026-08-21T08:05:30"
                    |> Expect.equal (Just { year = 2026, month = 8, day = 21, hour = 8, minute = 5, second = 30 })
        , test "an empty field is no time at all" <|
            \_ -> Wallclock.parseLocalDateTime "" |> Expect.equal Nothing
        , test "a half-typed date is no time at all" <|
            \_ -> Wallclock.parseLocalDateTime "2026-08" |> Expect.equal Nothing
        , test "a date with no time is no time at all" <|
            \_ -> Wallclock.parseLocalDateTime "2026-08-21" |> Expect.equal Nothing
        , test "junk is no time at all" <|
            \_ -> Wallclock.parseLocalDateTime "not a date" |> Expect.equal Nothing
        , test "non-numeric parts are no time at all" <|
            \_ -> Wallclock.parseLocalDateTime "2026-aug-21T08:00" |> Expect.equal Nothing
        ]


durationTests : Test
durationTests =
    describe "duration"
        [ test "nothing at all" <|
            \_ -> Wallclock.duration 0 |> Expect.equal "0m"
        , test "under a minute rounds to nothing rather than disappearing" <|
            \_ -> Wallclock.duration 20 |> Expect.equal "0m"
        , test "minutes alone" <|
            \_ -> Wallclock.duration (45 * 60) |> Expect.equal "45m"
        , test "the last minute before an hour" <|
            \_ -> Wallclock.duration (59 * 60) |> Expect.equal "59m"
        , test "an hour pads its minutes" <|
            \_ -> Wallclock.duration 3600 |> Expect.equal "1h 00m"
        , test "hours and minutes" <|
            \_ -> Wallclock.duration (4 * 3600 + 33 * 60) |> Expect.equal "4h 33m"
        , test "past a day it keeps counting in hours" <|
            \_ -> Wallclock.duration (25 * 3600) |> Expect.equal "25h 00m"
        , test "minutesSeconds pads the seconds" <|
            \_ -> Wallclock.minutesSeconds 240 |> Expect.equal "4:00"
        , test "minutesSeconds of a part minute" <|
            \_ -> Wallclock.minutesSeconds 185 |> Expect.equal "3:05"
        ]


timeOfDayAfterTests : Test
timeOfDayAfterTests =
    let
        -- 2026-08-21T11:00:00Z
        elevenHundred =
            Time.millisToPosix 1787396400000
    in
    describe "timeOfDayAfter"
        [ test "no time ahead is the time itself" <|
            \_ -> Wallclock.timeOfDayAfter Time.utc elevenHundred 0 |> Expect.equal "11:00"
        , test "reads in the given zone" <|
            \_ -> Wallclock.timeOfDayAfter (Time.customZone 60 []) elevenHundred 0 |> Expect.equal "12:00"
        , test "hours ahead" <|
            \_ -> Wallclock.timeOfDayAfter Time.utc elevenHundred (2.5 * 3600) |> Expect.equal "13:30"
        , test "says so when it lands tomorrow" <|
            \_ -> Wallclock.timeOfDayAfter Time.utc elevenHundred (25 * 3600) |> Expect.equal "12:00 +1d"
        , test "counts the days over a long ride" <|
            \_ -> Wallclock.timeOfDayAfter Time.utc elevenHundred (100 * 3600) |> Expect.equal "15:00 +4d"
        , test "a zone can push the arrival into the next day on its own" <|
            \_ -> Wallclock.timeOfDayAfter (Time.customZone 60 []) elevenHundred (13 * 3600) |> Expect.equal "01:00 +1d"

        -- The reason timeOfDayAfter rounds before it formats: the arrival and the time to go
        -- are always shown together, so they must never disagree about the odd minute.
        , fuzz (Fuzz.intRange 0 (400 * 3600)) "the arrival is always exactly `duration` after now" <|
            \secondsAhead ->
                let
                    minutesFromClock text =
                        case String.split ":" (String.left 5 text) of
                            [ h, m ] ->
                                Maybe.map2 (\hh mm -> hh * 60 + mm) (String.toInt h) (String.toInt m)
                                    |> Maybe.withDefault -1

                            _ ->
                                -1

                    arrival =
                        Wallclock.timeOfDayAfter Time.utc elevenHundred (toFloat secondsAhead)

                    daysAhead =
                        case String.split " +" arrival of
                            [ _, days ] ->
                                String.dropRight 1 days |> String.toInt |> Maybe.withDefault 0

                            _ ->
                                0
                in
                (minutesFromClock arrival + daysAhead * 1440)
                    - minutesFromClock (Wallclock.timeOfDayAfter Time.utc elevenHundred 0)
                    |> Expect.equal (round (toFloat secondsAhead / 60))
        ]
