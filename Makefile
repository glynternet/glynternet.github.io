ELM_OPTIMIZE ?= --optimize

image: gems calendars wasm cuesheet.js elevationprofile.js
	docker build -t glynternet/glynternet:latest .

gems:
	docker build -f gems.Dockerfile -t glynternet/glynternet-gems:latest .

serve: image
	docker run --rm \
		--volume="${PWD}:/srv/jekyll:Z" \
		--publish [::1]:4000:4000 \
		-it glynternet/glynternet:latest \
		jekyll serve --trace --livereload

sh:
	docker run --rm \
		--volume="${PWD}:/srv/jekyll:Z" \
		-it glynternet/glynternet:latest \
		bash

.PHONY: wasm
wasm:
	${MAKE} -C wasm

# phony because elm-live produces this and I can't work out how to produce to another path and still work in dev mode.
.PHONY: cuesheet.js
cuesheet.js:
	docker run --rm \
		--volume="${PWD}:/elmapp:Z" \
		glynternet/elm:latest \
		sh -c "cd elmapp/elm/cuesheet && elm make ${ELM_OPTIMIZE} ./src/Main.elm --output=../../data/$@"

# phony because elm-live produces this and I can't work out how to produce to another path and still work in dev mode.
.PHONY: elevationprofile.js
elevationprofile.js:
	docker run --rm \
		--volume="${PWD}:/elmapp:Z" \
		glynternet/elm:latest \
		sh -c "cd elmapp/elm/elevationprofile && elm make ${ELM_OPTIMIZE} ./src/Main.elm --output=../../data/$@"

elm-sh:
	docker run --rm -it \
		--volume="${PWD}:/elmapp:Z" \
		glynternet/elm:latest \
		sh

elm-docker-image:
	docker build -f elm.Dockerfile -t glynternet/elm:latest .

calendars:
	${MAKE} -C _calendar