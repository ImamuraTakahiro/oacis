class RunsListDatatable

  HEADER  = ['<th>RunID</th>', '<th>status</th>', '<th>priority</th>',
             '<th>elapsed</th>',
             '<th>MPI</th>', '<th>OMP</th>', '<th>version</th>',
             '<th>created_at</th>', '<th>updated_at</th>', '<th>host(group)</th>', '<th>job_id</th>',
             '<th style="min-width: 18px; width: 1%;"></th>']
  SORT_BY = ["id", "status", "priority", "real_time",
             "mpi_procs", "omp_threads", "simulator_version",
             "created_at", "updated_at", "submitted_to", "job_id", "id"]

  def initialize(runs, view)
    @view = view
    @runs = runs
  end

  def as_json(options = {})
    {
      draw: @view.params[:draw].to_i,
      recordsTotal: @runs.count,
      recordsFiltered: @runs.count,
      data: data
    }
  end

private

  def data
    a = []
    runs_lists.each do |run|
      tmp = []
      tmp << @view.link_to( @view.shortened_id_monospaced(run.id), @view.run_path(run) )
      tmp << @view.raw( @view.status_label(run.status) )
      tmp << Run::PRIORITY_ORDER[run.priority]
      tmp << @view.formatted_elapsed_time(run.real_time)
      tmp << run.mpi_procs
      tmp << run.omp_threads
      tmp << run.simulator_version
      tmp << @view.distance_to_now_in_words(run.created_at)
      tmp << @view.distance_to_now_in_words(run.updated_at)
      host_like = run.submitted_to || run.host_group
      tmp << (host_like ? @view.link_to( host_like.name, host_like ) : "---")
      tmp << @view.shortened_job_id(run.job_id)
      trash = OACIS_READ_ONLY ? @view.raw('<i class="fa fa-trash-o">')
        : @view.link_to( @view.raw('<i class="fa fa-trash-o">'), run, remote: true, method: :delete, data: {confirm: 'Are you sure?'})
      tmp << trash
      a << tmp
    end
    a
  end

  def runs_lists
    @runs.order_by(sort_column_direction).without(:result).skip(page).limit(per_page)
  end

  def page
    @view.params[:start].to_i
  end

  def per_page
    @view.params[:length].to_i > 0 ? @view.params[:length].to_i : 10
  end

  def sort_column_direction
    a = [sort_columns,sort_directions].transpose
    Hash[*a.flatten]
  end

  def sort_columns
    return ["updated_at"] if @view.params["order"].nil?
    @view.params["order"].keys.map do |key|
      SORT_BY[@view.params["order"][key]["column"].to_i]
    end
  end

  def sort_directions
    return ["desc"] if @view.params["order"].nil?
    @view.params["order"].keys.map do |key|
      @view.params["order"][key]["dir"] == "desc" ? "desc" : "asc"
    end
  end
end

