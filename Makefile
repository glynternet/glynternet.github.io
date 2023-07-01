build:
	docker build -t glynternet/glynternet:latest .

serve:
	docker run --rm \
		--volume="${PWD}:/srv/jekyll:Z" \
		--publish [::1]:4000:4000 \
		-it glynternet/glynternet:latest \
		jekyll serve

sh:
	docker run --rm \
		--volume="${PWD}:/srv/jekyll:Z" \
		-it glynternet/glynternet:latest \
		bash

# phony because elm-live produces this and I can't work out how to produce to another path and still work in dev mode.
.PHONY: routesheet.js
routesheet.js:
	docker run \
		--volume="${PWD}:/elmapp:Z" \
		glynternet/elm:latest \
		sh -c "cd elmapp/elm/routesheet && elm make ./src/Main.elm --output=../../data/$@"

elm-sh:
	docker run -it \
		--volume="${PWD}:/elmapp:Z" \
		glynternet/elm:latest \
		sh

elm-docker-image:
	docker build -f elm.Dockerfile -t glynternet/elm:latest .