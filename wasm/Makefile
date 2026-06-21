# Deterministic build ID derived from the source (main.go + module files)
# rather than Go's default environment-dependent hash. This keeps the committed
# binary byte-stable across rebuilds and Go toolchain patch versions (so it
# stops showing as modified on every build), while still changing whenever the
# source changes. -trimpath drops absolute paths so it's also stable across
# checkout locations. Read the ID back with: go tool buildid ../data/gpx.wasm
BUILDID := $(shell cat main.go go.mod go.sum | sha256sum | cut -c1-16)

build:
	GOOS=js GOARCH=wasm go build -trimpath -ldflags=-buildid=$(BUILDID) -o ../data/gpx.wasm