module Wallclock exposing
    ( CivilDateTime
    , civilSeconds
    , daysFromCivil
    , duration
    , localDateTime
    , minutesSeconds
    , parseLocalDateTime
    , secondsOfDay
    , timeOfDayAfter
    )

{-| Reading and writing times the way a rider reads them: a time of day, a span of hours and
minutes, and the wall-clock datetime a `datetime-local` input deals in.

Kept apart from the app because none of it knows anything about routes, and because
`daysFromCivil` is the one piece of arithmetic here that could be subtly wrong without ever
looking wrong — it wants tests, and a module is what makes tests possible.

-}

import Time



-- SPANS


{-| A span of time in hours and minutes, the units an arrival is worth stating in. Rounds to
the nearest minute, so a span shorter than one still reads as "0m" rather than disappearing.
-}
duration : Float -> String
duration seconds =
    let
        totalMinutes =
            round (seconds / 60)
    in
    if totalMinutes < 60 then
        String.fromInt totalMinutes ++ "m"

    else
        String.fromInt (totalMinutes // 60) ++ "h " ++ String.padLeft 2 '0' (String.fromInt (modBy 60 totalMinutes)) ++ "m"


minutesSeconds : Int -> String
minutesSeconds seconds =
    String.fromInt (seconds // 60) ++ ":" ++ String.padLeft 2 '0' (String.fromInt (modBy 60 seconds))



-- TIMES OF DAY


{-| A time of day in the rider's own zone, `secondsAhead` after `from`, with any days it lands
past today spelled out — a ride long enough to finish tomorrow is exactly the ride that needs
telling.

`secondsAhead` is rounded to whole minutes first, and to the same minute `duration` would round
it to. Both are displayed together, so a clock that dropped the leftover seconds while the
duration rounded them up would show an arrival a minute off the time to go.

The day count comes from the time of day rather than the calendar, so it stays right over
however many days the span runs without any date arithmetic.

-}
timeOfDayAfter : Time.Zone -> Time.Posix -> Float -> String
timeOfDayAfter zone from secondsAhead =
    let
        wholeMinutesAhead =
            toFloat (round (secondsAhead / 60) * 60)

        at =
            Time.millisToPosix (Time.posixToMillis from + round (wholeMinutesAhead * 1000))

        pad =
            String.fromInt >> String.padLeft 2 '0'

        daysAhead =
            floor ((toFloat (secondsOfDay zone from) + wholeMinutesAhead) / 86400)
    in
    pad (Time.toHour zone at)
        ++ ":"
        ++ pad (Time.toMinute zone at)
        ++ (if daysAhead > 0 then
                " +" ++ String.fromInt daysAhead ++ "d"

            else
                ""
           )


secondsOfDay : Time.Zone -> Time.Posix -> Int
secondsOfDay zone at =
    Time.toHour zone at * 3600 + Time.toMinute zone at * 60 + Time.toSecond zone at



-- CIVIL DATETIMES


{-| A wall-clock date and time with no zone attached, which is all a `datetime-local` input
deals in and all that is needed to difference two of them.
-}
type alias CivilDateTime =
    { year : Int
    , month : Int
    , day : Int
    , hour : Int
    , minute : Int
    , second : Int
    }


localDateTime : Time.Zone -> Time.Posix -> CivilDateTime
localDateTime zone at =
    { year = Time.toYear zone at
    , month = monthNumber (Time.toMonth zone at)
    , day = Time.toDay zone at
    , hour = Time.toHour zone at
    , minute = Time.toMinute zone at
    , second = Time.toSecond zone at
    }


{-| Reads what a `datetime-local` input holds: "2026-08-21T08:00", with or without seconds.
Anything else — an empty field, a half-typed date — is no time at all rather than a guess.
-}
parseLocalDateTime : String -> Maybe CivilDateTime
parseLocalDateTime text =
    case String.split "T" text of
        [ date, timeOfDay ] ->
            case ( String.split "-" date, String.split ":" timeOfDay ) of
                ( [ year, month, day ], hours :: minutes :: rest ) ->
                    Maybe.map5
                        (\y mo d h mi ->
                            CivilDateTime y mo d h mi (List.head rest |> Maybe.andThen String.toFloat |> Maybe.withDefault 0 |> floor)
                        )
                        (String.toInt year)
                        (String.toInt month)
                        (String.toInt day)
                        (String.toInt hours)
                        (String.toInt minutes)

                _ ->
                    Nothing

        _ ->
            Nothing


{-| Seconds from the epoch to a wall-clock datetime, read as if it were UTC. Only ever used to
difference two of them, where whatever offset they share cancels out.
-}
civilSeconds : CivilDateTime -> Int
civilSeconds t =
    daysFromCivil t.year t.month t.day * 86400 + t.hour * 3600 + t.minute * 60 + t.second


{-| Days from 1970-01-01 to a civil date, by Howard Hinnant's `days_from_civil`. It relies on
integer division truncating toward zero, which Elm's `//` does, and is what lets two wall-clock
datetimes be differenced across any number of days without a calendar library.
-}
daysFromCivil : Int -> Int -> Int -> Int
daysFromCivil year month day =
    let
        shiftedYear =
            if month <= 2 then
                year - 1

            else
                year

        era =
            (if shiftedYear >= 0 then
                shiftedYear

             else
                shiftedYear - 399
            )
                // 400

        yearOfEra =
            shiftedYear - era * 400

        dayOfYear =
            (153
                * (if month > 2 then
                    month - 3

                   else
                    month + 9
                  )
                + 2
            )
                // 5
                + day
                - 1

        dayOfEra =
            yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
    in
    era * 146097 + dayOfEra - 719468


monthNumber : Time.Month -> Int
monthNumber month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
