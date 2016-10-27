class RunsController < ApplicationController

  def index
    # check if worker is alive
    workers = [JobSubmitterWorker, JobObserverWorker, ServiceWorker]
    if workers.all? {|worker| worker.alive? }
      if workers.all? {|worker| worker.log_recently_updated? }
        flash.now[:notice] = "Worker process is running"
      else
        flash.now[:alert] = "Worker process exists, but may be hanging up"
      end
    else
      if OACIS_READ_ONLY
        flash.now[:notice] = "READ_ONLY mode. Worker is not running"
      else
        flash.now[:alert] = "Worker process is not running"
      end
    end

    respond_to do |format|
      format.html
    end
  end

  def _jobs_table
    stat = params["run_status"].to_sym
    render json: RunsListDatatable.new(Run.where(status: stat), view_context)
  end

  def show
    @run = Run.find(params[:id])
    @param_set = @run.parameter_set
    respond_to do |format|
      format.html
      format.json
    end
  end

  def create
    if params[:preview_button]
      preview
      return
    end

    @param_set = ParameterSet.find(params[:parameter_set_id])

    num_runs = 1
    num_runs = params[:num_runs].to_i if params[:num_runs]
    raise 'params[:num_runs] is invalid' unless num_runs > 0

    @runs = []
    num_runs.times do |i|
      run = @param_set.runs.build(permitted_run_params)
      @runs << run if run.save
    end

    respond_to do |format|
      if @runs.present?
        message = "#{@runs.count} run#{@runs.size > 1 ? 's were' : ' was'} successfully created"
        format.json { render json: @runs, status: :created, location: @param_set}
        @messages = {success: [message]}
        format.js
      else
        format.json {
          render json: @runs.map{ |r| r.errors }, status: :unprocessable_entity
        }
        run = @param_set.runs.build(permitted_run_params)
        run.valid?
        @messages = {error: run.errors.full_messages }
        format.js
      end
    end
  end

  def _analyses_list
    run = Run.find(params[:id])
    render json: AnalysesListDatatable.new(run.analyses, view_context)
  end

  def preview
    param_set = ParameterSet.find(params[:parameter_set_id])
    run = param_set.runs.build(permitted_run_params)
    @error_messages = run.valid? ? [] : run.errors.full_messages
    @script = JobScriptUtil.script_for(run) if run.valid?
    respond_to do |format|
      format.js {
        render action: "preview"
      }
    end
  end

  def destroy
    @run = Run.find(params[:id])
    @run.discard

    respond_to do |format|
      format.json { head :no_content }
      format.js
    end
  end

  private
  def permitted_run_params
    if params[:run]["submitted_to"].present?
      id = params[:run]["submitted_to"]
      if Host.where( id: id ).exists?
        host_param_keys = Host.find(id).host_parameter_definitions.map(&:key)
        params.require(:run).permit(:mpi_procs, :omp_threads, :priority, :submitted_to, host_parameters: host_param_keys)
      elsif HostGroup.where( id: id ).exists?
        modify_params_for_host_group_submission
        params.require(:run).permit(:mpi_procs, :omp_threads, :priority, :host_group)
      end
    else  # manual submission
      params.require(:run).permit(:mpi_procs, :omp_threads, :priority)
    end
  end

  def modify_params_for_host_group_submission
    params[:run]["host_group"] = params[:run]["submitted_to"]
    params[:run].delete("submitted_to")
  end
end
