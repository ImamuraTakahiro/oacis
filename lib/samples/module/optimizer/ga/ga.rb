require 'json'
require_relative '../../OACIS_module.rb'
require_relative '../../OACIS_module_data.rb'

class Ga < OacisModule

  # this definition is used by OACIS_module_installer
  def self.definition
    h = {}
    h["seed"]=0
    h["population"] = 10
    h["iteration"] = 100
    num_crossover=(h["population"]/2).to_i
    num_mutation=h["population"]-num_crossover
    h["generate_children"]=[{"type"=>"crossover","definition"=>{"selection"=>{"type"=>"tournament", "definition"=>{"tournament_size"=>4}}, "type"=>"1point", "population_size"=>num_crossover}},{"type"=>"mutation", "definition"=>{"type"=>"uniform_distribution", "selection"=>{"type"=>"random"}, "rate"=>0.3, "population_size"=>num_mutation}}]
    h["selection"]={"type"=>"ranking"}
    h["maximize"]=true
    h
  end

  # data contains definitions whose values are given as ParameterSet.v in OACIS_module_simulator
  def initialize(_input_data)
    super(_input_data)

    #create some aliases
    @ga_definition = Ga.definition.keys.map {|k| {k => module_data.data["_input_data"][k]}}.inject({}) {|h, val| h.merge!(val)}
  end

  def create_or_restore_module_data
    super
    if File.exists?("_output.json")
      @prng = Random.new.marshal_load(JSON.parse(module_data.data["_status"]["rnd_algorithm"]))
    else
      @prng = Random.new(module_data.data["_input_data"]["seed"])
      module_data.data["_status"]["rnd_algorithm"]=@prng.marshal_dump.to_json
    end
  end

  #override
  def create_module_data
    GaOptimizerData.new
  end

  private
  def get_parents(num, definition)
    parents = []
    case definition["type"]
    when "random"
      begin
        parents.push(@prng.rand(module_data.get_parents(@num_iterations-1).length)).uniq!
      end while parents.length < num
    when "tournament"
      begin
        pa = get_parents(2, {"type"=>"random"})
        pa1_result = module_data.get_parent(@num_iterations-1, pa.first)["output"].first
        pa2_result = module_data.get_parent(@num_iterations-1, pa.last)["output"].first
        if @ga_definition["maximize"]
          better_pa = pa1_result > pa2_result ? pa.first : pa.last
        else
          better_pa = pa1_result > pa2_result ? pa.last : pa.first
        end
        parents.push(better_pa)
      end while parents.length < num
    end
    parents[0..(num-1)]
  end

  def n_point_crossover(definition)
    children = []
    begin
      pos = @prng.rand(managed_parameters.map {|x| x if x["range"].present?}.compact.length-1).truncate + 1
      a = []
      b = []
      parents = get_parents(2, definition["selection"])
      input1 = module_data.get_parent_position(@num_iterations-1, parents.first)
      input2 = module_data.get_parent_position(@num_iterations-1, parents.last)
      input1.each_with_index do |val, i|
        if i < pos
          a[i] = input1[i]
          b[i] = input2[i]
        else
          a[i] = input2[i]
          b[i] = input1[i]
        end
      end
      puts "operation:n_point_crossover,iteration:#{@num_iterations},parents:[#{parents.first}, #{parents.last}]"
      children.push(a)
      children.push(b)
    end while children.length < definition["population_size"]
    children[0..(definition["population_size"]-1)]
  end

  def uniform_distribution_mutation(definition)
    children = []
    begin
      x = []
      index = get_parents(1, definition["selection"]).first
      parent_input = module_data.get_parent(@num_iterations-1, index)["input"]
      mpara = managed_parameters_table
      parent_input.each_with_index do |val, d|
        x[d] = val + @prng.rand(mpara[d]["range"][1] - mpara[d]["range"][0]) + mpara[d]["range"][0]
      end
      puts "operation:uniform_distribution_mutation,iteration:#{@num_iterations}, parents:[#{parent_input}], childlen:[#{x}]"
      children.push(x)
    end while children.length < definition["population_size"]
    children
  end

  def generate_children_ga
    children = []
    @ga_definition["generate_children"].each do |operation|
      case operation["type"]
      when "crossover"
        definition = operation["definition"]
        case definition["type"]
        when "1point"
          op_children=[]
          while op_children.length <= definition["population_size"]
            n_point_crossover(definition).each do |child|
              op_children.push(child)
            end
          end
          children += op_children[0..definition["population_size"]-1]
        else
          STDERR.puts definition["type"].to_s+" is not defined in crossover operations."
          exit(-1)
        end
      when "mutation"
        definition = operation["definition"]
        case definition["type"]
        when "uniform_distribution"
          op_children=[]
          while op_children.length <= definition["population_size"]
            uniform_distribution_mutation(definition).each do |child|
              op_children.push(child)
            end
          end
          children+=op_children[0..definition["population_size"]-1]
        else
          STDERR.puts definition["type"].to_s+" is not defined in mutation operations."
          exit(-1)
        end
      else
        STDERR.puts operation["type"]+" is not defined as operations."
        exit(-1)
      end
    end
    children.each_with_index do |child, i|
      module_data.set_child_input(@num_iterations, i, child)
    end
  end

  def create_children_ga
    @ga_definition["population"].times do |i|
      managed_parameters_table.each_with_index do |mp_table, d|
        x = nil
        case mp_table["type"]
        when "Integer"
          width = (mp_table["range"][1] - mp_table["range"][0]).to_i
          x = @prng.rand(width) + mp_table["range"][0]
        when "Float"
          width = (mp_table["range"][1] - mp_table["range"][0]).to_f
          x = @prng.rand(width) + mp_table["range"][0]
        when "String"
          x = mp_table["range"][@prng.rand(mp_table["range"].length)]
        when "Boolean"
          x = mp_table["range"][@prng.rand(mp_table["range"].length)]
        end
        module_data.set_child_input(@num_iterations, i, x, d)
      end
    end
  end

  def select_population
    module_data.data["data_sets"][@num_iterations].each_with_index do |data, index|
      module_data.get_child(@num_iterations, index)["output"] = data["output"]
    end

    case @ga_definition["selection"]["type"]
    when "ranking"
      if @num_iterations==0
        module_data.get_children(@num_iterations).each_with_index do |child, i|
          module_data.set_parent(@num_iterations, i, child)
        end
      else
        all_members = (module_data.get_children(@num_iterations) + module_data.get_parents(@num_iterations-1)).uniq
        if @ga_definition["maximize"]
          all_members = all_members.sort{|a, b| (b["output"][0] <=> a["output"][0])}
        else
          all_members = all_members.sort{|a, b| (a["output"][0] <=> b["output"][0])}
        end
        all_members[0..@ga_definition["population"]-1].each_with_index do |new_p, i|
          module_data.set_parent(@num_iterations, i, new_p)
        end
      end
    end
  end

  def update_status
    select_population

    #update best
    fitness_array = module_data.get_parents(@num_iterations).map{|d| d["output"][0]}
    if @ga_definition["maximize"]
      best_key = fitness_array.sort.last
    else
      best_key = fitness_array.sort.first
    end
    best_index = fitness_array.index(best_key)
    module_data.set_best(@num_iterations, module_data.get_parent(@num_iterations, best_index))
  end

  #override
  def get_target_fields(result)
    [result.try(:fetch, "Fitness")]
  end

  #override
  def generate_runs #define generate_runs afeter update_particle_positions
    @num_iterations == 0 ? create_children_ga : generate_children_ga
    super
  end

  #override
  def evaluate_runs
    super
    update_status
 end

  #override
  def finished?
    b=[]
    b.push(@num_iterations >= @ga_definition["iteration"])
    return b.any?
  end
end

class GaOptimizerData < OacisModuleData

  private
  #overwrite
  def data_struct
    h = super
    h["best"] = [] # h["best"][index] = [{"input"=>[],"output"=>[]}, {"input"=>[], ...}, ...]
    h["children"] = [] # h["children"][index] = [{"input"=>[],"output"=>[]}, {"input"=>[], ...}, ...]
    h["parents"] = [] # h["children"][index] = [{"input"=>[],"output"=>[]}, {"input"=>[], ...}, ...]
    h
  end

  public
  #overwrite
  def data
    @data ||= data_struct
  end

  def get_best(iteration)
    data["best"][iteration] ||= {"input"=>[],"output"=>[]}
  end

  def set_best(iteration, val)
    raise "\"input\" key is necessary" unless val.keys.include?("input")
    raise "\"output\" key is necessary" unless val.keys.include?("output")
    val.each do |key,val|
      get_best(iteration)[key]=val
    end
  end

  def get_best_position(iteration, index, dim)
    a = get_best(iteration)
    a["input"][dim]
  end

  def get_children(iteration)
    data["children"][iteration] ||= []
  end

  def get_child(iteration, index)
    a = get_children(iteration)
    a[index] ||= {"input"=>[],"output"=>get_output(iteration, index)}
  end

  def set_child(iteration, index, val)
    raise "val must be a Hash" unless val.is_a?(Hash)
    raise "\"input\" key is necessary" unless val.keys.include?("input")
    raise "\"output\" key is necessary" unless val.keys.include?("output")
    c = get_children(iteration, index)
    h = get_datasets(iteration, index)
    val.each do |k, v|
      c[k] = v
      h[k] = v
    end
  end

  def set_child_input(iteration, index, val, *dim)
    c = get_child(iteration, index)
    h = get_datasets(iteration, index)
    if dim.empty?
      val.each_with_index do |v, i|
        c["input"][i] = v
        h["input"][i] = v
      end
    else
      c["input"][dim[0]] = val
      h["input"][dim[0]] = val
    end
  end

  def get_parents(iteration)
    data["parents"][iteration] ||= []
  end

  def get_parent(iteration, index)
    a = get_parents(iteration)
    a[index] ||= {"input"=>[],"output"=>[]}
  end

  def set_parent(iteration, index, val)
    raise "val must be a Hash" unless val.is_a?(Hash)
    raise "\"input\" key is necessary" unless val.keys.include?("input")
    raise "\"output\" key is necessary" unless val.keys.include?("output")
    h = get_parent(iteration, index)
    val.each do |k, v|
      h[k] = v
    end
  end

  def get_parent_position(iteration, index, *dim)
    a = get_parents(iteration)
    a[index] ||= {"input"=>[], "output"=>[]}
    dim.empty? ? a[index]["input"] : a[index]["input"][dim[0]]
  end

  def get_fitness(iteration, index)
    get_output(iteration, index)
  end

  def set_fitness(iteration, index, val)
    set_output(iteration, index, val)
  end
end
