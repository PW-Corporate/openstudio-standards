# AUTHOR:  Anton Szilasi
# DESCRIPTION:  Docker build for running Rakefile in this repo across different OS versions
# OpenStudio/ruby set up taken from - https://github.com/NREL/docker-openstudio/blob/master/Dockerfile

# Pull base image.
FROM nrel/openstudio:3.1.0

MAINTAINER Anton Szilasi ajszilasi@gmail.com

WORKDIR /usr/local/src

# Install bundler
RUN gem install bundle

### Cannot do anything more with build as installing openstudio gems requires all the local OpenStudio files must do this once container exists!
### Once build container mount this dir on container /usr/local/src and run
### 1. bundle install
### 2. bundle update
### 3. bundle exec rake library:export_speed to export

CMD [ "/bin/bash" ]