BUILD_DIR = ../data/calendars

all: fat-biking bike-events

.PHONY: ${BUILD_DIR}/fat-biking.ics ${BUILD_DIR}/bike-events.ics

fat-biking:
	yaml2ics ./fat-biking.yml > "${BUILD_DIR}/fat-biking.ics"

bike-events:
	yaml2ics ./bike-events.yml > "${BUILD_DIR}/bike-events.ics"
