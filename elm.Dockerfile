FROM node:21-alpine3.18

# Both pinned: elm.json says the app needs 0.19.1, and `npm install -g elm` has since
# started resolving to 0.19.2, which refuses to build it. An unpinned rebuild of this
# image would break `make route.js` with no change to the repo.
#
# elm-test lives here rather than in an image of its own so that it and `make route.js`
# compile against exactly the same Elm.
RUN npm install -g elm@0.19.1-6 elm-test@0.19.1-revision12
