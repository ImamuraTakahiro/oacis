require 'spec_helper'

describe Parameter do

  before(:each) do
    @sim = FactoryGirl.create(:simulator)
    @valid_attr = {:sim_parameters => {"L" => 32, "T" => 1.0}}
  end

  describe "validation" do

    it "should create a Parameter when valid attributes are given" do
      lambda {
        @sim.parameters.create!(@valid_attr)
      }.should_not raise_error
    end

    it "should not be balid when simulator is not related" do
      param = Parameter.new(@valid_attr)
      param.should_not be_valid
    end

    it "should not be valid when sim_parameters does not exist" do
      invalid_attr = @valid_attr
      invalid_attr.delete(:sim_parameters)
      built_param = @sim.parameters.build(invalid_attr)
      built_param.should_not be_valid
    end

    it "should not be valid when sim_parameters is not a Hash" do
      invalid_attr = @valid_attr.update({:sim_parameters => "xxx"})
      prev_parameters_count = @sim.parameters.count
      lambda {
        @sim.parameters.create!(invalid_attr)
      }.should raise_error
      @sim.parameters.count.should == prev_parameters_count
    end

    it "should not be valid when keys of sim_parameters are not consistent its Simulator" do
      built_param = @sim.parameters.build(@valid_attr.update({:sim_parameters => {"L"=>32}}))
      built_param.should_not be_valid
    end

    it "should not be valid when sim_parameters is not unique" do
      @sim.parameters.create!(@valid_attr)
      built = @sim.parameters.build(@valid_attr)
      built.should_not be_valid
      err = built.errors.messages
      err.should have_key(:sim_parameters)
      err[:sim_parameters].find {|x|
        x =~ /identical/
      }.should be_true
    end

    it "identical sim_parameters is valid for a differnet simulator" do
      @sim.parameters.create!(@valid_attr)

      sim2 = FactoryGirl.create(:simulator)
      built_param = sim2.parameters.build(@valid_attr)
      built_param.should be_valid
    end

    it "should cast the values of sim_parameters properly" do
      updated_attr = @valid_attr.update(:sim_parameters => {"L"=>"32","T"=>"2.0"})
      built = @sim.parameters.build(updated_attr)
      built.should be_valid
      built[:sim_parameters]["L"].should == 32
      built[:sim_parameters]["T"].should == 2.0
    end

    it "should be valid once it is saved with valid attributes" do
      prm = @sim.parameters.first
      prm.should be_valid
    end
  end

  describe "relations" do

    before(:each) do
      @parameter = @sim.parameters.first
    end

    it "has simulator method" do
      @parameter.should respond_to(:simulator)
    end

    it "has runs method" do
      @parameter.should respond_to(:runs)
    end
  end

  describe "result directory" do

    before(:each) do
      @root_dir = ResultDirectory.root
      FileUtils.rm_r(@root_dir) if FileTest.directory?(@root_dir)
      FileUtils.mkdir(@root_dir)
    end

    after(:each) do
      FileUtils.rm_r(@root_dir) if FileTest.directory?(@root_dir)
    end

    it "is created when a new item is added" do
      sim = FactoryGirl.create(:simulator, :parameters_count => 0)
      prm = sim.parameters.create!(@valid_attr)
      FileTest.directory?(ResultDirectory.parameter_path(prm)).should be_true
    end

    it "is not created when validation fails" do
      sim = FactoryGirl.create(:simulator, :parameters_count => 0)
      prm = sim.parameters.create(@valid_attr.update({:sim_parameters => {"L"=>32}}))
      Dir.entries(ResultDirectory.simulator_path(sim)).should == ['.', '..'] # i.e. empty directory
    end
  end

  describe "#dir" do

    it "returns the result directory of the parameter" do
      sim = FactoryGirl.create(:simulator, :parameters_count => 1, :runs_count => 0)
      prm = sim.parameters.first
      prm.dir.should == ResultDirectory.parameter_path(prm)
    end
  end

  describe "#parameters_with_different" do

    before(:each) do
      h = { "L"=>{"type"=>"Integer", "default" => 50, "description" => "First parameter"},
            "T"=>{"type"=>"Float", "default" => 1.0, "description" => "Second parameter"},
            "P"=>{"type"=>"Float", "default" => 1.0, "description" => "Third parameter"}
      }
      sim = FactoryGirl.create(:simulator, :parameter_definitions => h, :parameters_count => 0)
      5.times do |n|
        val = {"L" => 1, "T" => (n+1)*1.0, "P" => 1.0}
        sim.parameters.create( sim_parameters: val )
      end
      4.times do |n|
        val = {"L" => n+2, "T" => 1.0, "P" => 1.0}
        sim.parameters.create( sim_parameters: val )
      end
      4.times do |n|
        val = {"L" => 1, "T" => 1.0, "P" => (n+2)*1.0}
        sim.parameters.create( sim_parameters: val )
      end
      @prm = sim.parameters.first
    end

    it "returns parameters whose sim_parameter is same as self except for the specified key" do
      prms_L = @prm.parameters_with_different("L")
      prms_L.count.should == 5
      prms_L.each do |prm_L|
        prm_L.sim_parameters["T"].should == @prm.sim_parameters["T"]
      end

      prms_T = @prm.parameters_with_different("T")
      prms_T.count.should == 5
      prms_T.each do |prm_T|
        prm_T.sim_parameters["L"].should == @prm.sim_parameters["L"]
      end
    end

    it "includes self" do
      found = @prm.parameters_with_different("L").find(@prm)
      found.should be_a(Parameter)
    end
  end
end
