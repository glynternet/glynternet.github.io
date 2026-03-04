package main

import (
	"encoding/json"
	"fmt"
	"syscall/js"

	"github.com/glynternet/gpx/pkg/elevation"
	"github.com/tkrajina/gpxgo/gpx"
)

func main() {
	fmt.Println("Profile wasm started")
	js.Global().Set("elevationProfileData", jsonResultFunc1(elevationProfileData))
	js.Global().Set("splitProfile", jsonResultFunc1(splitProfile))
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
	gpxData, err := gpx.ParseBytes([]byte(arg.String()))
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
