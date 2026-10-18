module ProfilePreparation exposing (Data, prepare)

{-| One transient preparation for the selected route. The app advances the source revision
on upload, track navigation and state import; never compare full trackpoint lists for a hit.
-}

import GpxApi


type alias Data =
    { sourceRevision : Int
    , minElevation : Float
    , maxElevation : Float
    , intensityTau : Maybe Float
    , intensityPoints : List { distance : Float, intensity : Float }
    , minIntensity : Float
    , maxIntensity : Float
    }


prepare : Int -> Maybe Float -> List GpxApi.TrackPoint -> Maybe Data -> Data
prepare sourceRevision intensityTau trackpoints previous =
    case previous of
        Just prepared ->
            if prepared.sourceRevision == sourceRevision then
                case intensityTau of
                    Nothing ->
                        prepared

                    Just _ ->
                        if prepared.intensityTau == intensityTau then
                            prepared

                        else
                            prepareIntensity intensityTau trackpoints prepared

            else
                prepare sourceRevision intensityTau trackpoints Nothing

        Nothing ->
            prepareIntensity intensityTau
                trackpoints
                { sourceRevision = sourceRevision
                , minElevation = trackpoints |> List.map .elevation |> List.minimum |> Maybe.withDefault 1
                , maxElevation = trackpoints |> List.map .elevation |> List.maximum |> Maybe.withDefault 1
                , intensityTau = Nothing
                , intensityPoints = []
                , minIntensity = 1 / 0
                , maxIntensity = -(1 / 0)
                }


prepareIntensity : Maybe Float -> List GpxApi.TrackPoint -> Data -> Data
prepareIntensity intensityTau trackpoints prepared =
    let
        points =
            intensityTau |> Maybe.map (\tau -> computeIntensity tau trackpoints) |> Maybe.withDefault []

        ( minimum, maximum ) =
            List.foldl (\point ( low, high ) -> ( min low point.intensity, max high point.intensity ))
                ( 1 / 0, -(1 / 0) )
                points
    in
    { prepared
        | intensityTau = intensityTau
        , intensityPoints = points
        , minIntensity = minimum
        , maxIntensity = maximum
    }


computeIntensity : Float -> List GpxApi.TrackPoint -> List { distance : Float, intensity : Float }
computeIntensity tau trackPoints =
    case trackPoints of
        [] ->
            []

        first :: rest ->
            let
                ( _, result ) =
                    List.foldl
                        (\current ( ( prev, prevIntensity ), acc ) ->
                            let
                                deltaD =
                                    current.distance - prev.distance

                                grade =
                                    if deltaD > 0 then
                                        (current.elevation - prev.elevation) / deltaD

                                    else
                                        0

                                climbingGrade =
                                    max 0 grade

                                decay =
                                    e ^ (-deltaD / tau)

                                newIntensity =
                                    decay * prevIntensity + (1 - decay) * climbingGrade
                            in
                            ( ( current, newIntensity )
                            , { distance = current.distance, intensity = newIntensity } :: acc
                            )
                        )
                        ( ( first, 0 ), [ { distance = first.distance, intensity = 0 } ] )
                        rest
            in
            List.reverse result
