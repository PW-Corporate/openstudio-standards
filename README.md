# Purpose

To create core speed resources from spreadsheet data

Data required:

1. construction_costs.csv
2. InputJSONData_SpaceLoads.csv
3. InputJSONData.xlsx
4. OpenStudio_Standards-speed(schedules).xlsx

Data generated:

1. construction_lib.osm (For speed engine and constructions measures) and an accompanying constructions_list.csv with all the constructions listed
2. SpeedSchedules.osm (For speed engine)
3. inputs_new.json - the input.json
# Consisting of:

A. construction_inputs_new.json
B. space_loads_inputs_new.json - Uses InputJSONData_SpaceLoads.csv
C. other_inputs_new.json - Uses InputJSONData.xlsx

Which are combined to form: inputs_new.json


Run with rake task export_speed:
https://github.com/PW-Corporate/openstudio-standards/blob/master/Rakefile#L245-L252



# PW Fork of OpenStudio-Standards

Install Ruby and OpenStudio as described below for either OpenStudio 3.2.0,3.1.0,3.0.0 or 2.9.1. Note if switching between versions of OpenStudio you will have to delete the `Gemfile.lock` file in the root directory of this repository.

Edit `./data/standards/OpenStudio_Standards.xslx`.

Note for Schedules: When pulling SPEED Schedules from dropbox make sure that all tabs EXCEPT Schedules are deleted and the schedules tab is named Schedules

Run the commands:
```
bundle update
bundle exec rake library:export_speed
```

JSON data files are generated in `./data/standards/` folder.

## Ruby 2.5.5 and OpenStudio 3.0.0

Follow installation instructions for [OpenStudio Extension Gem](https://github.com/NREL/openstudio-extension-gem/blob/develop/README.md)

## Ruby 2.2.4 and OpenStudio 2.9.1

### Windows Installation
Install Ruby using the [RubyInstaller](https://rubyinstaller.org/downloads/archives/) for [Ruby 2.2.4 (x64)](https://dl.bintray.com/oneclick/rubyinstaller/rubyinstaller-2.2.4-x64.exe).

Check the ruby installation returns the correct Ruby version (2.2.4):
```
ruby -v
```

Install bundler from the command line
```
gem install bundler -v 1.17.3
```

Install Devkit using the [mingw64](https://dl.bintray.com/oneclick/rubyinstaller/DevKit-mingw64-64-4.7.2-20130224-1432-sfx.exe) installer.

Open a command prompt, `cd <DEVKIT_INSTALL_DIR>` where Devkit is installed.  Run the following commands:

```
ruby dk.rb init
ruby dk.rb review
ruby dk.rb install
```

See Devkit [detailed instructions](https://github.com/oneclick/rubyinstaller/wiki/Development-Kit) if needed.

Install OpenStudio.  Create a file ```C:\Ruby22-x64\lib\ruby\site_ruby\openstudio.rb``` and point it to your OpenStudio installation by editing the contents.  E.g.:

```ruby
require 'C:\openstudio-2.9.1\Ruby\openstudio'
```

Verify your OpenStudio and Ruby configuration:
```
ruby -e "require 'openstudio'" -e "puts OpenStudio::Model::Model.new"
```

# OpenStudio-Standards

This library (a Ruby Gem) is an extension of the [OpenStudio SDK](https://www.openstudio.net/) with three main use-cases:

1. Create the DOE Prototype Buildings in OpenStudio format
2. Create a code baseline model from a proposed model
3. Check a model against a code/standard (not yet implemented)

## Online Documentation

If you are a user, please see the [Online Documentation](http://www.rubydoc.info/gems/openstudio-standards)
 for an overview of how the library is structured and how it is used.

## Developer Information

If you are a developer, see the [Developer Information](docs/DeveloperInformation.md) page.



