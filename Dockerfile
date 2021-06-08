# AUTHOR:  Anton Szilasi
# DESCRIPTION:  Docker build for running Rakefile in this repo across different OS versions
# OpenStudio/ruby set up taken from - https://github.com/NREL/docker-openstudio/blob/master/Dockerfile

# Pull base image.
FROM nrel/openstudio:3.0.1

MAINTAINER Anton Szilasi ajszilasi@gmail.com

WORKDIR /usr/local/src

# Install bundler
gem install bundle

# Install the ruby gems
RUN bundle install

bundle update

CMD [ "/bin/bash" ]