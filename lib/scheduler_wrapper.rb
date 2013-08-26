class SchedulerWrapper

  TYPES = ["none", "torque", "pjm"]

  attr_reader :type

  def initialize(type)
    unless TYPES.include?(type)
      raise ArgumentError.new("type must be selected from #{TYPES.inspect}")
    end
    @type = type
  end

  def submit_command(script)
    case @type
    when "none"
      "nohup bash #{script} > /dev/null 2>&1 < /dev/null &; basename #{script}"
    when "torque"
      "qsub #{script}"
    when "pjm"
      "pjsub #{script}"
    else
      raise "not supported"
    end
  end

  def all_status_command
    case @type
    when "none"
      "ps ux"
    when "torque"
      "qstat; pbsnodes -a"
    when "pjm"
      "pjstat"
    else
      raise "not supported"
    end
  end

  def status_command(job_id)
    case @type
    when "none"
      "ps ux | grep \"[#{job_id[0]}]#{job_id[1..-1]}\""
    when "torque"
      "qstat #{job_id}"
    when "pjm"
      "pjstat #{job_id}"
    else
      raise "not supported"
    end
  end

  def parse_remote_status(stdout)
    return :unknown if stdout.empty?
    case @type
    when "none"
      if stdout.present?
        :running
      end
    when "torque"
      stat = stdout.lines.to_a.last.split[4]
      case stat
      when /Q/
        :submitted
      when /C/
        :includable
      when /[RT]/
        :running
      else
        :unknown
      end
    when "pjm"
      stat = stdout.lines.to_a.last.split[3]
      case stat
      when /ACC|QUE/
        :submitted
      when /SIN|RDY|RNA|RUN|RNO|SOT/
        :running
      when /EXT|CCL/
        :includable
      else
        :unknown
      end
    else
      raise "not supported"
    end
  end

  def cancel_command(job_id)
    case @type
    when "none"
      "kill -- -`ps x -o \"pgid pid command\" | grep \"[#{job_id[0]}]#{job_id[1..-1]}\" | awk '{print $1}'`"
    when "torque"
      "qdel #{job_id}"
    when "pjm"
      "pjdel #{job_id}"
    else
      raise "not supported"
    end
  end
end