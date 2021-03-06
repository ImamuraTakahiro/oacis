namespace :db do

  desc "Update schema"
  task :update_schema => :environment do
    $stderr.puts "updating schema..."

    q = Analysis.where(parameter_set: nil)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |anl|
      analyzable = anl.analyzable
      if analyzable.is_a?(Run)
        anl.update_attribute(:parameter_set_id, analyzable.parameter_set.id)
      elsif analyzable.is_a?(ParameterSet)
        anl.update_attribute(:parameter_set_id, analyzable.id)
      end
      progressbar.increment
    end

    q = Run.where(priority: nil)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |run|
      run.timeless.update_attribute(:priority, 1)
      progressbar.increment
    end

    q = Host.where(status: nil)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |host|
      host.timeless.update_attribute(:status, :enabled)
      progressbar.increment
    end

    q = Run.where(status: :cancelled)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |run|
      run.destroy
      progressbar.increment
    end
    q = Analysis.where(status: :cancelled)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |anl|
      anl.destroy
      progressbar.increment
    end

    client = Mongoid::Clients.default
    if client.collections.find {|col| col.name== "worker_logs" }
      raise "collection is not capped" unless client["worker_logs"].capped?
    else
      client.command(create: "worker_logs", capped: true, size: 1048576)
      $stderr.puts "capped collection worker_logs was created"
    end

    q = Simulator.where(to_be_destroyed: nil)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |sim|
      sim.update_attribute(:to_be_destroyed, false)
      progressbar.increment
    end

    q = Analyzer.where(to_be_destroyed: nil)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |azr|
      azr.update_attribute(:to_be_destroyed, false)
      progressbar.increment
    end

    # to fix issue #460
    q = Simulator.where(:h.exists => true)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |sim|
      sim.unset(:h)
      progressbar.increment
    end

    q = Analyzer.where(:h.exists => true)
    progressbar = ProgressBar.create(total: q.count, format: "%t %B %p%% (%c/%C)")
    q.each do |azr|
      azr.unset(:h)
      progressbar.increment
    end
  end
end
