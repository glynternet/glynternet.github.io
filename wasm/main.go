package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"syscall/js"

	"github.com/glynternet/gpx/pkg/elevation"
	gpxio "github.com/glynternet/gpx/pkg/io"
	gpxgo "github.com/tkrajina/gpxgo/gpx"
)

func main() {
	fmt.Println("Profile wasm started")
	js.Global().Set("elevationProfileData", jsonResultFunc1(elevationProfileData))
	js.Global().Set("splitProfile", jsonResultFunc1(splitProfile))
	js.Global().Set("splitsToGpx", jsonResultFunc1(splitsToGpx))
	select {}
}

func jsonResultFunc1[T any](fn func(js.Value) (T, error)) js.Func {
	return js.FuncOf(func(this js.Value, args []js.Value) any {
		if len(args) != 1 {
			return "Invalid no of arguments passed"
		}
		successResult, err := fn(args[0])
		if err == nil {
			success, marshallErr := json.Marshal(successResult)
			if marshallErr == nil {
				return string(success)
			}
			err = marshallErr
		}
		// error should never happen here
		marshal, _ := json.Marshal(struct {
			Error string `json:"error"`
		}{
			Error: err.Error(),
		})
		return string(marshal)
	})
}

func splitProfile(arg js.Value) (elevation.SplitResult, error) {
	var req elevation.SplitRequest
	if err := json.Unmarshal([]byte(arg.String()), &req); err != nil {
		return elevation.SplitResult{}, fmt.Errorf("parsing split request: %w", err)
	}
	switch req.Mode {
	case "equidistant":
		return elevation.SplitByDistance(req.Track, req.Count), nil
	case "waypoints":
		return elevation.SplitByWaypoints(req.Track, req.Distances), nil
	default:
		return elevation.SplitResult{}, fmt.Errorf("unknown split mode: %q", req.Mode)
	}
}

func elevationProfileData(arg js.Value) ([]elevation.Profile, error) {
	gpxData, err := gpxgo.ParseBytes([]byte(arg.String()))
	if err != nil {
		return nil, fmt.Errorf("parsing GPX data: %w", err)
	}
	if len(gpxData.Tracks) == 0 {
		return nil, fmt.Errorf("gpx contains no tracks")
	}
	profiles, err := elevation.CalculateProfiles(gpxData.Tracks, gpxData.Waypoints)
	if err != nil {
		return nil, fmt.Errorf("calculating profiles from parsed data: %w", err)
	}
	return profiles, nil
}

func splitsToGpx(arg js.Value) (string, error) {
	var segments []elevation.Profile
	if err := json.Unmarshal([]byte(arg.String()), &segments); err != nil {
		return "", fmt.Errorf("parsing segments: %w", err)
	}
	var tracks []gpxgo.GPXTrack
	for i, seg := range segments {
		var points []gpxgo.GPXPoint
		for _, tp := range seg.Track {
			points = append(points, gpxgo.GPXPoint{
				Point: gpxgo.Point{
					Latitude:  tp.Lat,
					Longitude: tp.Lon,
					Elevation: *gpxgo.NewNullableFloat64(tp.Elevation),
				},
			})
		}
		tracks = append(tracks, gpxgo.GPXTrack{
			Name:     fmt.Sprintf("Split %d", i+1),
			Segments: []gpxgo.GPXTrackSegment{{Points: points}},
		})
	}
	var buf bytes.Buffer
	if err := gpxio.Write(&buf, gpxgo.GPX{Tracks: tracks}); err != nil {
		return "", fmt.Errorf("writing gpx: %w", err)
	}
	return buf.String(), nil
}
