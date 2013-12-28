require 'spec_helper'
require File.join(Rails.root, 'lib/cli/oacis_cli')

describe OacisCli do

  describe "#job_parameter_template" do

    before(:each) do
      @host = FactoryGirl.create(:host_with_parameters)
    end

    it "outputs a template of job_parameters" do
      at_temp_dir {
        options = { host_id: @host.id.to_s, output: 'job_parameters.json'}
        OacisCli.new.invoke(:job_parameter_template, [], options)
        File.exist?('job_parameters.json').should be_true
        expect {
          JSON.load(File.read('job_parameters.json'))
        }.not_to raise_error
      }
    end

    it "outputs a template having default job_parameters" do
      at_temp_dir {
        options = { host_id: @host.id.to_s, output: 'job_parameters.json'}
        OacisCli.new.invoke(:job_parameter_template, [], options)

        expected = {
          "host_id" => @host.id.to_s,
          "host_parameters" => {"param1" => nil, "param2" => "XXX"},
          "mpi_procs" => 1,
          "omp_threads" => 1
        }
        JSON.load(File.read('job_parameters.json')).should eq expected
      }
    end

    context "when host id is invalid" do

      it "raises an exception" do
        at_temp_dir {
          options = { host_id: "DO_NOT_EXIST", output: 'job_parameters.json'}
          expect {
            OacisCli.new.invoke(:job_parameter_template, [], options)
          }.to raise_error
        }
      end
    end

    context "when dry_run option is specified" do

      it "does not create output file" do
        at_temp_dir {
          options = {
            host_id: @host.id.to_s,
            output: 'job_parameters.json',
            dry_run: true
          }
          OacisCli.new.invoke(:job_parameter_template, [], options)
          File.exist?('job_parameters.json').should be_false
        }
      end
    end
  end

  describe "#create_runs" do

    before(:each) do
      @host = FactoryGirl.create(:host_with_parameters)
      @sim = FactoryGirl.create(:simulator,
                                parameter_sets_count: 2, runs_count: 0,
                                support_mpi: true, support_omp: true)
      @sim.executable_on.push @host
      @sim.save!
    end

    def create_parameter_set_ids_json(parameter_sets, path)
      File.open(path, 'w') {|io|
        ids = parameter_sets.map {|ps| {"parameter_set_id" => ps.id.to_s} }
        io.puts ids.to_json
        io.flush
      }
    end

    def create_job_parameters_json(path)
      File.open(path, 'w') {|io|
        job_parameters = {
          "host_id" => @host.id.to_s,
          "host_parameters" => {"param1" => "foo", "param2" => "bar"},
          "mpi_procs" => 2,
          "omp_threads" => 8
        }
        io.puts job_parameters.to_json
        io.flush
      }
    end

    def invoke_create_runs
      create_parameter_set_ids_json(@sim.parameter_sets, 'parameter_set_ids.json')
      create_job_parameters_json('job_parameters.json')
      options = {
        parameter_sets: 'parameter_set_ids.json',
        job_parameters: 'job_parameters.json',
        number_of_runs: 3,
        output: 'run_ids.json'
      }
      OacisCli.new.invoke(:create_runs, [], options)
    end

    it "creates runs for each parameter_set" do
      at_temp_dir {
        expect {
          invoke_create_runs
        }.to change { Run.count }.by(6)
      }
    end

    it "creates run having correct attributes" do
      at_temp_dir {
        invoke_create_runs
        run = @sim.parameter_sets.first.runs.first
        run.submitted_to.should eq @host
        run.mpi_procs.should eq 2
        run.omp_threads.should eq 8
        run.host_parameters.should eq({"param1" => "foo", "param2" => "bar"})
      }
    end

    it "outputs ids of created runs in json" do
      at_temp_dir {
        invoke_create_runs

        File.exist?('run_ids.json').should be_true
        expected = Run.all.map {|run| {"run_id" => run.id.to_s} }.sort_by {|h| h["run_id"]}
        JSON.load(File.read('run_ids.json')).should =~ expected
      }
    end

    context "when run exists" do

      before(:each) do
        @ps1 = @sim.parameter_sets.first
        FactoryGirl.create_list(:run, 5, parameter_set: @ps1)
        @ps2 = @sim.parameter_sets[1]
        FactoryGirl.create_list(:run, 1, parameter_set: @ps2)
      end

      it "iterates creation of runs up to the specified number" do
        at_temp_dir {
          expect {
            invoke_create_runs
          }.to change { Run.count }.by(2)
        }
      end

      it "outputs ids of created and existing runs up to the specified number" do
        at_temp_dir {
          invoke_create_runs

          File.exist?('run_ids.json').should be_true
          runs = @ps1.reload.runs.limit(3).to_a + @ps2.reload.runs.limit(3)
          expected = runs.map {|run| {"run_id" => run.id.to_s} }.sort_by {|h| h["run_id"]}
          JSON.load(File.read('run_ids.json')).should =~ expected
        }
      end
    end

    context "when job_parameters are invalid" do

      def create_invalid_job_parameters_json(path)
        File.open(path, 'w') {|io|
          job_parameters = {
            "host_id" => @host.id.to_s,
            "host_parameters" => {"param1" => "foo"}, # Do not set param2
            "mpi_procs" => 2,
            "omp_threads" => 8
          }
          io.puts job_parameters.to_json
          io.flush
        }
      end

      it "raises an exception" do
        at_temp_dir {
          create_parameter_set_ids_json(@sim.parameter_sets, 'parameter_set_ids.json')
          create_invalid_job_parameters_json('job_parameters.json')
          options = {
            parameter_sets: 'parameter_set_ids.json',
            job_parameters: 'job_parameters.json',
            number_of_runs: 3,
            output: 'run_ids.json'
          }
          expect {
            OacisCli.new.invoke(:create_runs, [], options)
          }.to raise_error
        }
      end
    end

    context "when parameter_set_ids.json is invalid" do

      def create_invalid_parameter_set_ids_json(parameter_sets, path)
        File.open(path, 'w') {|io|
          ids = parameter_sets.map {|ps| {"parameter_set_id" => ps.id.to_s} }
          ids.push( {"parameter_set_id" => "DO_NOT_EXIST"} )
          io.puts ids.to_json
          io.flush
        }
      end

      def invoke_create_runs_with_invalid_parameter_set_ids
        create_invalid_parameter_set_ids_json(@sim.parameter_sets, 'parameter_set_ids.json')
        create_job_parameters_json('job_parameters.json')
        options = {
          parameter_sets: 'parameter_set_ids.json',
          job_parameters: 'job_parameters.json',
          number_of_runs: 3,
          output: 'run_ids.json'
        }
        OacisCli.new.invoke(:create_runs, [], options)
      end

      it "raises an exception" do
        at_temp_dir {
          expect {
            invoke_create_runs_with_invalid_parameter_set_ids
          }.to raise_error
        }
      end

      it "outputs run_ids if successfully created runs exist" do
        at_temp_dir {
          begin
            invoke_create_runs_with_invalid_parameter_set_ids
          rescue
          end
          File.exist?('parameter_set_ids.json').should be_true
        }
      end

    end

    context "when dry_run option is given" do

      def invoke_create_runs_with_dry_run
        create_parameter_set_ids_json(@sim.parameter_sets, 'parameter_set_ids.json')
        create_job_parameters_json('job_parameters.json')
        options = {
          parameter_sets: 'parameter_set_ids.json',
          job_parameters: 'job_parameters.json',
          number_of_runs: 3,
          output: 'run_ids.json',
          dry_run: true
        }
        OacisCli.new.invoke(:create_runs, [], options)
      end

      it "does not save Runs" do
        at_temp_dir {
          expect {
            invoke_create_runs_with_dry_run
          }.to_not change { Run.count }
        }
      end

      it "does not create output file" do
        at_temp_dir {
          invoke_create_runs_with_dry_run
          File.exist?('run_ids.json').should be_false
        }
      end
    end
  end

  describe "#run_status" do

    before(:each) do
      @sim = FactoryGirl.create(:simulator, parameter_sets_count: 2, runs_count: 3)
    end

    def create_run_ids_json(runs, path)
      File.open(path, 'w') do |io|
        run_ids = runs.map {|run| {"run_id" => run.id.to_s} }
        io.puts run_ids.to_json
        io.flush
      end
    end

    it "shows number of runs for each status in json" do
      at_temp_dir {
        create_run_ids_json(Run.all, 'run_ids.json')
        options = {run_ids: 'run_ids.json'}
        captured = capture(:stdout) {
          OacisCli.new.invoke(:run_status, [], options)
        }

        loaded = JSON.load(captured)
        loaded["total"].should eq 6
        loaded["created"].should eq 6
        loaded["finished"].should eq 0
      }
    end
  end
end