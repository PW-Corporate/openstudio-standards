require 'json'
require 'git'

base_path = File.dirname(__FILE__)

construction_inputs = nil
File.open(File.join(base_path, 'construction_inputs_new.json')) do |file|
  construction_inputs = JSON.parse(file.read)
end

space_loads_inputs = nil
File.open(File.join(base_path, 'space_loads_inputs_new.json')) do |file|
  space_loads_inputs = JSON.parse(file.read)
end

other_inputs = nil
File.open(File.join(base_path, 'other_inputs_new.json')) do |file|
  other_inputs = JSON.parse(file.read)
end

g = Git.open(File.join(File.dirname(__FILE__),'..','..'))

version_info = {}
version_info['pw_openstudio_standards_git_sha'] = g.log.first.sha
version_info['pw_openstudio_standards_describe'] = g.describe

File.write(File.join(File.dirname(__FILE__),'construction_lib.osm'), '### Produced by : openstudio-standards describe' << g.describe << '\n\n', 0)
File.write(File.join(File.dirname(__FILE__),'SpeedSchedules.osm'), '### Produced by : openstudio-standards describe' << g.describe << '\n\n', 0)

# combine inputs
inputs = {}
inputs['version_info'] = version_info
inputs['Project_Information'] = other_inputs['Project_Information']
inputs['Site_Context'] = other_inputs['Site_Context']
inputs['Geometry'] = other_inputs['Geometry']
inputs['Envelope'] = other_inputs['Envelope']
inputs['Constructions'] = construction_inputs['Constructions']
inputs['Space_Layout'] = other_inputs['Space_Layout']
inputs['Space_Loads'] = space_loads_inputs['Space_Loads']
inputs['HVAC'] = other_inputs['HVAC']
inputs['Daylighting'] = other_inputs['Daylighting']
inputs['Photovoltaics'] = other_inputs['Photovoltaics']

inputs.each_key do |key|
  if inputs[key].nil?
    STDOUT.flush
    raise "Error: No input data for #{key}"
  end
end

# Inputs JSON
File.open(File.join(base_path, 'inputs_new.json'), 'w') do |f|
  f.write(JSON.pretty_generate(inputs))
end
