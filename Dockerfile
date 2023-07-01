# this is just to cache the deps defined in the Gemfile so that it doesn't have to be done everytime serve is called
FROM jekyll/jekyll:3.8

COPY Gemfile Gemfile.lock /srv/jekyll/

RUN jekyll build