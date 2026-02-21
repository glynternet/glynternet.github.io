# this is just to cache the deps defined in the Gemfile so that it doesn't have to be done everytime serve is called.
# TDBM: DOES THIS ACTUALLY DEPLOY AS V4?
FROM jvconseil/jekyll-docker:4.3.3
#FROM jekyll/jekyll:4.2.2

RUN gem install bundler -v "2.6.8" -N

COPY --chown=jekyll:jekyll Gemfile Gemfile.lock /srv/jekyll/

RUN bundle install
