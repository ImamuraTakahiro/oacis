class ServiceWorker < DaemonSpawn::Base

  INTERVAL = 60

  WORKER_PID_FILE = Rails.root.join('tmp', 'pids', "service_worker_#{Rails.env}.pid")
  WORKER_LOG_FILE = Rails.root.join('log', "service_worker_#{Rails.env}.log")

  def start(args)
    @logger = Logger.new(STDOUT, 7)
    @logger.level = Logger::INFO
    @logger.info("starting")

    @term_received = false
    trap('TERM') {
      @term_received = true
      @logger.info("TERM received. stopping")
    }

    loop do
      CacheUpdater.perform(@logger)
      break if @term_received
      sleep INTERVAL
      break if @term_received
    end

    @logger.info("stopped")
  end

  def stop
    # Never called because trap('TERM') is overwritten
  end

  def self.alive?
    if File.file?(WORKER_PID_FILE)
      pid = (IO.read(WORKER_PID_FILE).to_i)
      DaemonSpawn.alive? pid
    else
      false
    end
  end

  # return true if the time stamp of the log file is updated within five minutes
  LOG_UPDATE_THRESHOLD = 60 * 5 # 5 minutes
  def self.log_recently_updated?
    if File.file?(WORKER_LOG_FILE)
      s = File.stat(WORKER_LOG_FILE)
      return true if Time.now - s.mtime < LOG_UPDATE_THRESHOLD
    end
    false
  end
end

if $0 == __FILE__
  ServiceWorker.spawn!(log_file: ServiceWorker::WORKER_LOG_FILE,
                       pid_file: ServiceWorker::WORKER_PID_FILE,
                       sync_log: true,
                       working_dir: Rails.root,
                       singleton: true,
                       timeout: 30
                       )
end
