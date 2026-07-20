BUILD_DIR = ../data/calendars
DATA_DIR = ../_data

all: cycling-events

# The outputs of both rules are gitignored, so on a fresh clone (notably in CI) their
# directories may not exist at all and have to be created before writing into them.
cycling-events: ${DATA_DIR}/cycling_events.yml
	mkdir -p "${BUILD_DIR}"
	python3 generate_ics.py ./cycling-events.yml > "${BUILD_DIR}/cycling-events.ics"

${DATA_DIR}/cycling_events.yml: ./cycling-events.yml
	mkdir -p "${DATA_DIR}"
	cp ./cycling-events.yml "${DATA_DIR}/cycling_events.yml"
