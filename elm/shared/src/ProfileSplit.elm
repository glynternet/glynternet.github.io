module ProfileSplit exposing (internalDistances, liveRange, pointDistances)

{-| The position-dependent inputs to profile splitting. Keep these independent of app state
so request suppression uses exactly the same boundaries as segment construction.
-}

import List.Extra
import Route exposing (EditableTrack, PointRef)


{-| WASM supplies the route ends itself. Repeated or endpoint boundaries would create empty
segments, so compare and send only sorted, unique distances inside the route.
-}
internalDistances : Float -> List Float -> List Float
internalDistances finishDistance =
    List.sort
        >> List.Extra.unique
        >> List.filter (\distance -> distance > 0 && distance < finishDistance)


pointDistances : Maybe Float -> EditableTrack -> List PointRef -> List Float
pointDistances position track =
    List.filterMap (Route.refDistance position track)
        >> internalDistances (Route.lastTrackpointDistance track.trackpoints)


{-| The effective live window, including clamping at either route end. Different positions
can produce the same window, so the range is the dependency to compare before rebuilding.
-}
liveRange : { window | liveLookbehind : Float, liveLookahead : Float } -> Float -> Maybe Float -> ( Float, Float )
liveRange window finishDistance position =
    case position of
        Just distance ->
            ( max 0 (distance - window.liveLookbehind), min finishDistance (distance + window.liveLookahead) )

        Nothing ->
            ( 0, finishDistance )
