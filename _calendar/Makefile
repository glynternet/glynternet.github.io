BUILD_DIR = ../data/calendars
DATA_DIR = ../_data

all: fat-biking cycling-events

.PHONY: ${BUILD_DIR}/fat-biking.ics ${BUILD_DIR}/cycling-events.ics

fat-biking:
	yaml2ics ./fat-biking.yml > "${BUILD_DIR}/fat-biking.ics"

cycling-events: ${DATA_DIR}/cycling_events.yml
	yaml2ics ./cycling-events.yml > "${BUILD_DIR}/cycling-events.ics"

${DATA_DIR}/cycling_events.yml: ./cycling-events.yml
	cp ./cycling-events.yml "${DATA_DIR}/cycling_events.yml"
