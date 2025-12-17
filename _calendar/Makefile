BUILD_DIR = ../data/calendars
DATA_DIR = ../_data

all: cycling-events

cycling-events: ${DATA_DIR}/cycling_events.yml
	python3 generate_ics.py ./cycling-events.yml > "${BUILD_DIR}/cycling-events.ics"

${DATA_DIR}/cycling_events.yml: ./cycling-events.yml
	cp ./cycling-events.yml "${DATA_DIR}/cycling_events.yml"
