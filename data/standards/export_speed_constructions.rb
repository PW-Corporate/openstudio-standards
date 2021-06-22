require 'openstudio'
require 'openstudio-standards'
require 'json'
require_relative 'speed_constructions'
require 'pry-nav'

# Standards to export
templates = ['90.1-2007', '90.1-2010', '90.1-2013']

# Surface types to export
intended_surface_types = ['ExteriorRoof', 'ExteriorWall', 'GroundContactFloor', 'ExteriorWindow']

# Building categories to export
building_category = 'Nonresidential'

# Typical prefix
typical_prefix = 'Typical '

# Store the results
inputs = {}
csv_rows = []
model = OpenStudio::Model::Model.new

# Export each standard to JSON and OSM simultaneously
templates.each do |template|
  puts ''
  puts "*** Exporting constructions for #{template} ***"
  template_data = {} # Hash to store data for JSON level
  std = Standard.build(template)

  # Correct the U-value and SHGC for ExteriorWindow: Metal framing (all other) in 90.1-2013
  #
  # TODO Remove
  # Bug where the U-value and SHGC for ExteriorWindow: Metal framing (all other) in 90.1-2013 matches
  # the U-value for Vertical Glazing, 0%-40% of Wall: Metal framing, entrance door
  # instead of Vertical Glazing, 0%-40% of Wall: Metal framing, fixed
  if template == '90.1-2013'
    # Get the construction properties
    const_props = std.standards_data['construction_properties']

    # Loop through climate zones
    (1..8).each do |climate_zone|
      # Find the climate zone set that this climate zone falls into
      climate_zone = climate_zone.to_s
      climate_zone_set = "ClimateZone #{climate_zone}"

      # Find the U-value and SHGC for ExteriorWindow: Metal framing (curtainwall/storefront)
      search_criteria = {
          'template' => template,
          'climate_zone_set' => climate_zone_set,
          'intended_surface_type' => 'ExteriorWindow',
          'standards_construction_type' => 'Metal framing (curtainwall/storefront)',
          'building_category' => building_category
      }
      correct_props = std.model_find_object(std.standards_data['construction_properties'], **search_criteria)

      # Modify the props for all Metal framing (all other) to match Metal framing (curtainwall/storefront)
      const_props.each do |p|
        next unless p['intended_surface_type'] == 'ExteriorWindow'
        next unless p['climate_zone_set'] == climate_zone_set
        next unless p['building_category'] == building_category
        next unless p['standards_construction_type'] == 'Metal framing (all other)'
        old_u = p['assembly_maximum_u_value']
        old_shgc = p['assembly_maximum_solar_heat_gain_coefficient']
        old_ratio = p['assembly_minimum_vt_shgc']
        new_u = correct_props['assembly_maximum_u_value']
        new_shgc = correct_props['assembly_maximum_solar_heat_gain_coefficient']
        new_ratio = correct_props['assembly_minimum_vt_shgc']
        puts "TEMP BUGFIX ExteriorWindow Metal framing (all other) U: #{old_u} to #{new_u}, SHGC: #{old_shgc} to #{new_shgc}, ratio: #{old_ratio} to #{new_ratio}"
        p['assembly_maximum_u_value'] = correct_props['assembly_maximum_u_value']
        p['assembly_maximum_solar_heat_gain_coefficient'] = correct_props['assembly_maximum_solar_heat_gain_coefficient']
        p['assembly_minimum_vt_shgc'] = correct_props['assembly_minimum_vt_shgc']
      end
    end

    # Reassign the modified construction properties to the standard
    std.standards_data['construction_properties'] = const_props
  end

  # Loop through climate zones
  (1..8).each do |climate_zone|
    climate_zone = climate_zone.to_s
    cz_data = {} # Hash to store data for JSON level

    # Find the climate zone set that this climate zone falls into
    climate_zone_set = "ClimateZone #{climate_zone}"

    # Loop through surface types
    intended_surface_types.each do |intended_surface_type|
      surf_type_data = {} # Hash to store data for JSON level

      # Downselect construction properties to this template/climate_zone/surface type combination
      search_criteria = {
        'template' => template,
        'climate_zone_set' => climate_zone_set,
        'intended_surface_type' => intended_surface_type,
        'building_category' => building_category
      }
      const_props = std.model_find_objects(std.standards_data['construction_properties'], **search_criteria)

      # Get unique set of standards construction types (mass, wood-framed, etc.) for this surface type
      standards_construction_types = []
      const_props.each do |props|
        standards_construction_type = props['standards_construction_type']
        if standards_construction_types.include?(standards_construction_type)
          # Warn if there is more than one construction properties for a given standards_construction_type
          puts "ERROR There is more than one construction_properties entry for #{standards_construction_type} for: #{template}-#{climate_zone_set}-#{intended_surface_type}-#{building_category}"
          const_props.each do |cp|
            puts "...#{cp}"
          end
          next
        else
          standards_construction_types << standards_construction_type
        end
      end

      # Only export Unheated GroundContactFloor
      if intended_surface_type == 'GroundContactFloor'
        # puts("INFO only making Unheated GroundContactFloor constructions")
        standards_construction_types = ['Unheated']
      end

      # Make multiple constructions (default and upgrades) for each construction type
      standards_construction_types.sort.each do |standards_construction_type|
        const_type_data = {} # Hash to store data for JSON level

        # Downselect construction properties to this standards_construction_type (should just be 1)
        search_criteria = {
          'template' => template,
          'climate_zone_set' => climate_zone_set,
          'intended_surface_type' => intended_surface_type,
          'standards_construction_type' => standards_construction_type,
          'building_category' => building_category
        }
        props = std.model_find_object(std.standards_data['construction_properties'], **search_criteria)

        # Make sure that a construction is specified
        if props['construction'].nil?
          puts "ERROR No typical construction is specified for construction properties of: #{template}-#{climate_zone_set}-#{intended_surface_type}-#{standards_construction_type}-#{building_category}, cannot add constructions for this combination."
          next
        end

        # Each type of surface is generated differently
        case intended_surface_type
        when 'ExteriorRoof', 'ExteriorWall'
          type_data = {'Default' => '', 'Options' => []}
          r_val_data = {'Default' => '', 'Options' => []}

          # Make the default construction
          default, target_r_value_ip , target_r_value_si = SpeedConstructions.model_add_construction(std, model, props['construction'], props, climate_zone)
          # Prepend "Typical" for the default construction to si and ip name

          default_name = "#{typical_prefix}#{default.name.get.insert(default.name.get.index('|')+1, typical_prefix)}"
          if model.getConstructionByName(default_name).empty?
            default = default.clone(model).to_Construction.get
            default.setName(default_name)
          else
            default = model.getConstructionByName(default_name).get
          end

          type_data['Default'] = default.name.get.to_s
          r_val_data['Default'] = "#{target_r_value_ip} | #{target_r_value_si}"

          type_data['Options'] << default.name.get.to_s

          r_val_data['Options'] << "#{target_r_value_ip} | #{target_r_value_si}"

          # Add to the options

          # Make four incrementally better constructions
          r_val_ip_increases = case intended_surface_type
                               when 'ExteriorWall'
                                 [5.0, 10.0, 15.0, 20.0]
                               when 'ExteriorRoof'
                                 [10.0, 15.0, 20.0, 25.0]
                               end

          r_val_ip_increases.each do |r_val_increase_ip|
            upgraded_props = SpeedConstructions.upgrade_opaque_construction_properties(props, r_val_increase_ip)
            upgrade_construction , upgrade_r_value_ip, upgrade_r_value_si = SpeedConstructions.model_add_construction(std, model, upgraded_props['construction'], upgraded_props, climate_zone)
            # Get the modified R-value

            #if upgrade_construction.name.get.include? "IEAD" then binding.pry end

            #if upgrade_construction.name.get.to_s.include? 'Attic & Other Roof' then binding.pry end
            # Add to the options
            type_data['Options'] << upgrade_construction.name.get.to_s

            r_val_data['Options'] << "#{upgrade_r_value_ip.to_s} | #{upgrade_r_value_si.to_s}"
          end

          # Store the outputs
          const_type_data[SpeedConstructions.speed_enum(intended_surface_type, 'method') + '_Type'] = type_data
          const_type_data[SpeedConstructions.speed_enum(intended_surface_type, 'method') + '_R_Value'] = r_val_data
        when 'GroundContactFloor'
          type_data = {'Default' => '', 'Options' => []}

          # Make the default construction
          default = SpeedConstructions.model_add_construction(std, model, props['construction'], props, climate_zone).first
          # Prepend "Typical" for the default construction to si and ip name
          default_name = "#{typical_prefix}#{default.name.get.insert(default.name.get.index('|')+1, typical_prefix)}"
          if model.getConstructionByName(default_name).empty?
            default = default.clone(model).to_Construction.get
            default.setName(default_name)
          else
            default = model.getConstructionByName(default_name).get
          end
          # Get the F-Factor
          target_f_factor_ip = props['assembly_maximum_f_factor']
          # Infer U-Value
          target_u_value_ip = SpeedConstructions.infer_slab_u_value_from_f_factor(target_f_factor_ip)
          # Set the U-value of the construction properties
          props['assembly_maximum_u_value'] = target_u_value_ip
          # Add as the default
          type_data['Default'] = default.name.get.to_s
          # Add to the options
          type_data['Options'] << default.name.get.to_s

          # No options for GroundContactFloor

          # Store the outputs
          const_type_data = type_data
        when 'ExteriorWindow'
          type_data = {'Default' => '', 'Options' => []}

          # Make the default construction, using SimpleGlazing
          props['convert_to_simple_glazing'] = 'yes'
          # When window only returns construction as dont need ip and si value
          default = SpeedConstructions.model_add_construction(std, model, props['construction'], props, climate_zone).first
          # Prepend "Typical" for the default construction to si and ip name
          default_name = "#{typical_prefix}#{default.name.get.insert(default.name.get.index('|')+1, typical_prefix)}"
          if model.getConstructionByName(default_name).empty?
            default = default.clone(model).to_Construction.get
            default.setName(default_name)
          else
            default = model.getConstructionByName(default_name).get
          end
          # Add as the default
          type_data['Default'] = default.name.get.to_s
          # Add to the options
          type_data['Options'] << default.name.get.to_s

          # Make four incrementally better constructions
          shgc_decreases = [0.1, 0.2, 0.3, 0.4]
          u_val_decreases = [0.2, 0.3, 0.4, 0.5]

          shgc_decreases.zip(u_val_decreases).each do |shgc_decrease, u_val_decrease|
            upgraded_props = SpeedConstructions.upgrade_window_construction_properties(props, shgc_decrease, u_val_decrease)
            # Use SimpleGlazing for the beyond-code options
            upgraded_props['convert_to_simple_glazing'] = 'yes'
            upgrade = SpeedConstructions.model_add_construction(std, model, upgraded_props['construction'], upgraded_props, climate_zone).first
            # Add to the options
            type_data['Options'] << upgrade.name.get.to_s
          end

          # Store the outputs
          const_type_data[SpeedConstructions.speed_enum(intended_surface_type, 'method') + '_Type'] = type_data
        end

        surf_type_data[SpeedConstructions.speed_enum(standards_construction_type)] = const_type_data
      end
      cz_data[SpeedConstructions.speed_enum(intended_surface_type)] = surf_type_data
    end

    # Add one type of default Interior Walls
    intended_surface_type = 'InteriorWall'
    surf_type_data = {} # Hash to store data for JSON level
    method_data = {} # Hash to store data for JSON level

    default = SpeedConstructions.model_add_construction(std, model, 'Typical Interior Wall').first

    method_data['Default'] = default.name.get.to_s
    method_data['Options'] = [default.name.get.to_s]
    method_type = SpeedConstructions.speed_enum(intended_surface_type, 'method') + '_Type'
    surf_type_data[method_type] = method_data
    cz_data[SpeedConstructions.speed_enum(intended_surface_type)] = surf_type_data

    # Add one type of default Interior Floors
    intended_surface_type = 'InteriorFloor'
    surf_type_data = {} # Hash to store data for JSON level
    method_data = {} # Hash to store data for JSON level

    default = SpeedConstructions.model_add_construction(std, model, 'Typical Interior Floor').first

    method_data['Default'] = default.name.get.to_s
    method_data['Options'] = [default.name.get.to_s]
    method_type = SpeedConstructions.speed_enum(intended_surface_type, 'method') + '_Type'
    surf_type_data[method_type] = method_data
    cz_data[SpeedConstructions.speed_enum(intended_surface_type)] = surf_type_data

    template_data[SpeedConstructions.speed_enum(climate_zone)] = cz_data

    # Add a reversed floor (i.e. interior ceiling), add to construction list explicitly below
    reverse_floor = default.reverseConstruction
    reverse_floor.setName('Typical Interior Floor Reversed')

  end

  inputs[SpeedConstructions.speed_enum(template)] = template_data
end

# Add a shading construction, add to construction list explicitly below
shading = OpenStudio::Model::Construction.new(model)
shading_info = shading.standardsInformation
shading.setName('ShadingDevices')

shading_material = OpenStudio::Model::StandardOpaqueMaterial.new(model)
shading_material.setName('1 in. lightweight concrete highly reflective')
shading_material.setRoughness('MediumRough')
shading_material.setThickness(0.0254)
shading_material.setConductivity(2.31)
shading_material.setDensity(2321.99999999999)
shading_material.setSpecificHeat(814.22222222222)
shading_material.setThermalAbsorptance(0.1)
shading_material.setSolarAbsorptance(0.1)
shading_material.setVisibleAbsorptance(0.1)

layers = OpenStudio::Model::MaterialVector.new
layers << shading_material
shading.setLayers(layers)

# Add the Constructions key as the top level of the hash
inputs = {'Constructions' => inputs}

# Do a sizing run to calculate window properties with E+ using hard-coded VT values
puts ''
puts '*** Performing a sizing run to calculate window properties using E+ ***'
std = Standard.build('90.1-2007') # doesn't matter which one, properties aren't used
SpeedConstructions.do_window_property_sizing_run(std, model)

# Check the window construction properties in the name vs. the E+ properties
window_tol = 3.0
puts ''
puts "*** Checking window construction properties in names against E+ calculations using tolerance of #{window_tol}% ***"
SpeedConstructions.compare_window_construction_properties(std, model, window_tol)

# Check the opaque construction properties in the name vs. the E+ properties
r_tol = 3.0
puts ''
puts "*** Checking opaque construction properties in names against model inputs using tolerance of #{r_tol}% ***"
SpeedConstructions.compare_opaque_contruction_properties(std, model, r_tol)

# Inputs JSON
File.open("#{__dir__}/construction_inputs_new.json", 'w') do |f|
  f.write(JSON.pretty_generate(inputs, {:indent => "    "}))
end

# Save CSV that can be used to fill in cost data for next run

construction_costs = {}

# Read Construction Costs
options = { :headers => true }
File.open("#{__dir__}/construction_costs.csv", 'r') do |f|
  csv = CSV.parse(f.read, options)
  m2_per_ft2 = 10.7639

  csv.each do |construction_cost_row|

    construction_costs[construction_cost_row['construction_name_ip'].to_s] = 10.7639 * construction_cost_row['cost ($/ft2)'].to_f
  
  end
  
end

### Hash of constructions and their ip and si names comes in handy
construction_ip_si_names = {}

construction_names = {}
construction_csv = []
construction_csv << ['energy_code', 'climate_zone', 'surface_type', 'assembly_type', 'construction_name', 'ip_name' , 'si_name','r value ip','r value si','is_duplicate','ip match','si match','cost data']
constructions = inputs['Constructions']
constructions.keys.each do |energy_code_key|
  energy_code = constructions[energy_code_key]
  energy_code.keys.each do |climate_zone_key|
    climate_zone = energy_code[climate_zone_key]
    climate_zone.keys.each do |surface_type_key|
      surface_type = climate_zone[surface_type_key]
      surface_type.keys.each do |assembly_or_type_key|
        #binding.pry
        if /.*_Type/.match(assembly_or_type_key)
          ### This is ONLY for e.g Slab_Type, Int_Wall_Type ,Floor_Type
          type = surface_type[assembly_or_type_key]
          # If assembly_or_type_key contains Type 
          options = type['Options']
          next unless options
          options.each do |construction_name|
            is_duplicate = construction_names.include?(construction_name)

            construction_csv << [energy_code_key, climate_zone_key, surface_type_key, '', construction_name, "NA" ,"NA", "NA" , "NA" ,is_duplicate]

            # for costing 'IEAD Roof CZ5 R-31' and 'Typical IEAD Roof CZ5 R-31' are the same
            construction_names[construction_name] = true
            construction_names[typical_prefix + construction_name] = true
            construction_names[construction_name.gsub(typical_prefix,'')] = true
          end
        else
          assembly_type = surface_type[assembly_or_type_key]
          assembly_type.keys.each do |type_key|
            ##  
            ## Attic and Other

            next unless /.*_Type/.match(type_key) ## Exclude the R_values here
            type = assembly_type[type_key]
            options = type['Options']
            #puts type
            next unless options
            options.each do |construction_name|
              is_duplicate = construction_names.include?(construction_name)

              #binding.pry

              ip_name = construction_name.split('|')[0]

              si_name = construction_name.split('|')[1]
              
              #puts construction_name
              #puts type
              #binding.pry
              if surface_type_key != "Exterior_Window"

                ip_rvalue = surface_type[assembly_or_type_key][type_key.split('_')[0] + '_R_Value']['Options'][options.index construction_name].split('|')[0].strip

                si_rvalue = surface_type[assembly_or_type_key][type_key.split('_')[0] + '_R_Value']['Options'][options.index construction_name].split('|')[1].strip

                #si_rvalue.to_f

                #ip_rvalue.to_f

                ### Check R value in construction matches actual R-value

                ip_match = (ip_name.split('-').last.to_f == ip_rvalue.to_f).to_s

                si_match = (si_name.split('-').last.to_f == si_rvalue.to_f).to_s

                construction_ip_si_names[construction_name] = {'ip_name' => ip_name,'si_name' => si_name}

                cost_data = (construction_costs.include?(ip_name.rstrip))
            
                construction_csv << [energy_code_key, climate_zone_key, surface_type_key, assembly_or_type_key, construction_name, ip_name ,si_name , ip_rvalue , si_rvalue ,is_duplicate,ip_match,si_match,cost_data]

              else

                construction_ip_si_names[construction_name] = {'ip_name' => ip_name,'si_name' => si_name}

                cost_data = (construction_costs.include?(ip_name.rstrip))

                ## works but we dont need it
                # ip_uvalue = ip_name.split('U-')[1].split(' ')[0]

                # si_uvalue = si_name.split('U-')[1].split(' ')[0]

                # binding.pry

                construction_csv << [energy_code_key, climate_zone_key, surface_type_key, assembly_or_type_key, construction_name, ip_name ,si_name , "NA" , "NA" ,is_duplicate,"NA","NA",cost_data]
              end

              # for costing 'IEAD Roof CZ5 R-31' and 'Typical IEAD Roof CZ5 R-31' are the same
              construction_names[construction_name] = true
              construction_names[typical_prefix + construction_name] = true
              construction_names[construction_name.gsub(typical_prefix,'')] = true
            end
          end
        end
      end
    end
  end
end

puts "***"
puts " *** Starting to check costs - can see in construction_list.csv ***"
puts "***"

# Iterate through constructions not construction costs that way we can find constructions which have no costs, we dont care about costs that have no construction
construction_ip_si_names.each do |speed_construction|

    #binding.pry
    ### Item 5 is ip name

    #binding.pry
    # construction[:ip_name].to_s == construction_cost_row['construction_name_ip'].to_s
    # Get first as find returns an array 

    if construction_costs.include?(speed_construction[1]["ip_name"].rstrip)
      ## we got the cost for the construction from construction_costs.csv
      name = speed_construction[0]

      cost = construction_costs[speed_construction[1]["ip_name"].rstrip]

    else

      puts "Could not find cost for #{speed_construction[0]} in construction_costs.csv cannot add construction costs will add default costs cost data flag will be set to false in construction list"
      next
    end

    construction = model.getConstructionByName(name)
    if construction.empty?
      puts "XXX Warning: Cannot find construction '#{name}' to apply costs XXX"
      next
    end

    construction = construction.get

    if construction.lifeCycleCosts.size > 1
      puts "Warning: Construction '#{name}' has multiple existing costs, removing"
      construction.removeLifeCycleCosts
    end

    if construction.lifeCycleCosts.size == 1
      existing_lcc = construction.lifeCycleCosts[0]

      old_name = existing_lcc.nameString
      old_category = existing_lcc.category
      old_cost = existing_lcc.cost
      old_cost_units = existing_lcc.costUnits
      old_start_of_costs = existing_lcc.startOfCosts
      old_repeat_period_years = existing_lcc.repeatPeriodYears

      existing_lcc.setName("LCC_MAT - #{name}")
      existing_lcc.setCategory('Construction')
      existing_lcc.setCost(cost)
      existing_lcc.setCostUnits('CostPerArea')
      existing_lcc.setStartOfCosts('ServicePeriod')
      existing_lcc.setRepeatPeriodYears(20)

      new_name = existing_lcc.nameString
      new_category = existing_lcc.category
      new_cost = existing_lcc.cost
      new_cost_units = existing_lcc.costUnits
      new_start_of_costs = existing_lcc.startOfCosts
      new_repeat_period_years = existing_lcc.repeatPeriodYears

      diff = []
      diff << "name: #{old_name} -> #{new_name}" if old_name != new_name
      diff << "category: #{old_category} -> #{new_category}" if old_category != new_category
      diff << "cost: #{old_cost} -> #{new_cost}" if old_cost != new_cost
      diff << "cost_units: #{old_cost_units} -> #{new_cost_units}" if old_cost_units != new_cost_units
      diff << "start_of_costs: #{old_start_of_costs} -> #{new_start_of_costs}" if old_start_of_costs != new_start_of_costs
      diff << "repeat_period_years: #{old_repeat_period_years} -> #{new_repeat_period_years}" if old_repeat_period_years != new_repeat_period_years

      if !diff.empty?
        puts "Warning: Construction '#{name}' cost changed - #{diff.join(',')}"
      end

    else

      lcc = OpenStudio::Model::LifeCycleCost.new(construction)
      lcc.setName("LCC_MAT - #{name}")
      lcc.setCategory('Construction')
      lcc.setCost(cost)
      lcc.setCostUnits('CostPerArea')
      lcc.setStartOfCosts('ServicePeriod')
      lcc.setRepeatPeriodYears(20)
    end
end

# check that every construction has one cost associated
model.getConstructions.each do |construction|
  if construction.lifeCycleCosts.size != 1

    # don't add default costs to these constructions
    next if construction.nameString.match(/Typical Interior Floor Reversed/)

    default_cost = 99

    if construction.nameString.match(/ShadingDevices/)
      default_cost = 1076.39104167097
    end

    puts "Warning: Construction '#{construction.nameString}' has #{construction.lifeCycleCosts.size} cost objects, expected 1.  Adding default cost of $#{default_cost}/m2"

    construction.removeLifeCycleCosts
    lcc = OpenStudio::Model::LifeCycleCost.new(construction)
    lcc.setName("LCC_MAT - #{construction.nameString}")
    lcc.setCategory('Construction')
    lcc.setCost(default_cost)
    lcc.setCostUnits('CostPerArea')
    lcc.setStartOfCosts('ServicePeriod')
    lcc.setRepeatPeriodYears(20)
  end
end

# OSM library
model.save(SpeedConstructions.construction_lib_path, true)

# add hard coded constructions
construction_csv << ['', '', '', '', 'Typical Interior Floor Reversed', false]
construction_csv << ['', '', '', '', 'ShadingDevices', false]

CSV.open("#{__dir__}/constructions_list.csv", 'w') do |f|
  construction_csv.each do |line|
    f << line
  end
end




