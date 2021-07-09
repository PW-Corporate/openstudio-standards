require 'openstudio'
require 'openstudio-standards'
require 'csv'
require 'json'
#require 'pry-nav'

# Standards to export
templates = ['90.1-2007', '90.1-2010', '90.1-2013','90.1-2016'] #,'90.1-2019']

# Store the results
inputs = {}

# Load the SPEED space type schedule mapping
base_path = File.dirname(__FILE__)
csv_path = File.join(base_path, 'InputJSONData_SpaceLoads.csv')
speed_space_types = CSV.table(csv_path, header_converters: nil).map { |row| row.to_hash }

space_loads_issues = []

space_loads_issues << ['ASHRAE standard','ASHRAE space type','speed space type name','zero lpd','zero epd','occupancy_per_area is zero','lighting_fraction_radiant is nil','lighting_fraction_visible is nil','lighting_fraction_to_return_air is nil','electric_equipment_fraction_radiant is nil']

## lpd --> 3
## epd --> 4
## occupancy_per_area --> 5
## lighting_fraction_radiant --> 6
## lighting_fraction_visible --> 7
### lighting_fraction_to_return_air --> 8
### electric_equipment_fraction_radiant --> 9

# Export space loads for each standard to JSON
templates.each do |template|
  # Make a standard

  std = Standard.build(template)

  # Loop through space types
  speed_space_types.each do |spd_st|
    # Skip rows that are part of a different standard
    next unless spd_st['template'] == template

    # Get some commonly-use attributes
    template_speed = spd_st['template_speed']
    building_type_speed = spd_st['building_type_speed']
    space_type_speed = spd_st['space_type_speed']

    # Populate the template layer
    #binding.pry
    
    if inputs[template_speed].nil?
      inputs[template_speed] = {}
    end

    # Populate the building type layer
    if inputs[template_speed][building_type_speed].nil?
      inputs[template_speed][building_type_speed] = {}
    end

    # Find the corresponding openstudio-standards space type
    search_criteria = {
      'template' => spd_st['template'],
      'building_type' => spd_st['building_type'],
      'space_type' => spd_st['space_type']
    }
    #puts search_criteria
    ### this is taking data from OpenStudio_Standards_space_types.json which is in IP??? Check
    ### Can we just convert to si?
    data = std.model_find_object(std.standards_data['space_types'], search_criteria)
    if data.nil?
      puts "ERROR Could not find space type data for #{search_criteria}"
      next
    end


    # Hash to hold data for this space type
    st_props = {}

    space_type_column = [spd_st['template'],spd_st['space_type'],spd_st['space_type_speed'],'','','']

    #if spd_st['space_type'] == "College -  Conference" then binding.pry end
    if data["occupancy_per_area"].nil? then space_type_column[5] = 'x' end
    if data["lighting_fraction_radiant"].nil? then space_type_column[6] = 'x'end
    if data["lighting_fraction_visible"].nil? then space_type_column[7] = 'x' end
    if data["lighting_fraction_to_return_air"].nil? then space_type_column[8] = 'x' end
    if data["electric_equipment_fraction_radiant"].nil? then space_type_column[9] = 'x' end
    
    # Lighting
    if spd_st['lighting_per_area'] == 'x'
      st_props['Lighting_Power_Density'] = {}
      lpd = data['lighting_per_area'].to_f
      #binding.pry
      # Default
      st_props['Lighting_Power_Density']['Default'] = lpd.round(2)

      # Options
      lpd_multipliers = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
      lpd_options = []
      lpd_multipliers.each do |lpd_mult|
        lpd_options << (lpd * lpd_mult).round(2)
      end

      st_props['Lighting_Power_Density']['Options'] = lpd_options
    end

    # Equipment
    if spd_st['electric_equipment_per_area'] == 'x'
      st_props['Equipment_Power_Density'] = {}
      epd = data['electric_equipment_per_area'].to_f

      # Default
      st_props['Equipment_Power_Density']['Default'] = epd.round(2)

      # Options
      epd_multipliers = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
      epd_options = []
      epd_multipliers.each do |epd_mult|
        epd_options << (epd * epd_mult).round(2)
      end
      st_props['Equipment_Power_Density']['Options'] = epd_options
    end

    if lpd_options.include? 0 then space_type_column[3] = 'x' end
    if epd_options.include? 0 then space_type_column[4] = 'x' end

    space_loads_issues << space_type_column  
  
    # Outside Air
    st_props['Outside_Air'] = {}
    st_props['Outside_Air']['Default'] = 'Code'
    st_props['Outside_Air']['Options'] = ['Code', '30% Better', '40% Better', '50% Better']

    # Cooling Setpoint
    st_props['Cooling_Setpoint'] = {}
    st_props['Cooling_Setpoint']['Default'] = 75
    st_props['Cooling_Setpoint']['Options'] = [75]

    # Heating Setpoint
    st_props['Heating_Setpoint'] = {}
    st_props['Heating_Setpoint']['Default'] = 70
    st_props['Heating_Setpoint']['Options'] = [70]

    # Save properties to hash
    # if space_type_speed == 'College-Conference' then puts search_criteria ; puts st_props['Lighting_Power_Density']['Default'] end
    inputs[template_speed][building_type_speed][space_type_speed] = st_props
  end
end


# Add the Space_Loads key as the top level of the hash
inputs = {'Space_Loads' => inputs}

# Save results to disk
File.open(File.join(base_path, 'space_loads_inputs_new.json'), 'w') do |f|
  f.write(JSON.pretty_generate(inputs, {:indent => "    "}))
end

# Save warnings
CSV.open("#{__dir__}/space_loads_issues.csv", 'w') do |f|
  space_loads_issues.each do |line|
    f << line
  end
end
