build:
	docker build -t glynternet:latest .

serve:
	docker run --rm \
		--volume="${PWD}:/srv/jekyll:Z" \
		--publish [::1]:4000:4000 \
		-it glynternet:latest \
		jekyll serve

sh:
	docker run --rm \
		--volume="${PWD}:/srv/jekyll:Z" \
		-it glynternet:latest \
		bash
