ELM_OPTIMIZE ?= --optimize

image: gems calendars wasm route.js
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

.PHONY: route.js
route.js:
	docker run --rm \
		--user="$$(id -u):$$(id -g)" \
		--volume="${PWD}:/elmapp:Z" \
		glynternet/elm:latest \
		sh -c "cd elmapp/elm/route && elm make ${ELM_OPTIMIZE} ./src/Main.elm --output=../../data/$@"

.PHONY: elm-test
elm-test:
	docker run --rm \
		--user="$$(id -u):$$(id -g)" \
		--volume="${PWD}:/elmapp:Z" \
		--env HOME=/tmp \
		glynternet/elm:latest \
		sh -c "cd elmapp/elm/route && elm-test"

elm-sh:
	docker run --rm -it \
		--user="$$(id -u):$$(id -g)" \
		--volume="${PWD}:/elmapp:Z" \
		glynternet/elm:latest \
		sh

elm-docker-image:
	docker build -f elm.Dockerfile -t glynternet/elm:latest .

calendars:
	${MAKE} -C _calendar