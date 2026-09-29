# frozen_string_literal: true

# Runs a block in a forked process of its own process group and returns what
# it returns (via Marshal), or raises Overdue once `deadline` seconds pass.
# The bound holds whatever the block does: a loop wedged in a read, or a
# watchdog that never fires, is killed along with every process it forked.
module Supervised
  class Overdue < StandardError; end

  Crashed = Struct.new(:detail)

  module_function

  def run(deadline:, &)
    reader, writer = IO.pipe
    pid = fork { serve(reader, writer, &) }
    writer.close
    report = collected(pid, reader, Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline)
    stop(pid)
    raise(Overdue, "still running after #{deadline}s; killed its process group") unless report
    decoded(report)
  ensure
    reader.close
  end

  def serve(reader, writer, &)
    reader.close
    Process.setpgid(0, 0)
    writer.write(Marshal.dump(outcome(&)))
    writer.close
    exit!(0)
  end

  def outcome
    yield
  rescue StandardError, ScriptError => error
    Crashed.new("#{error.class}: #{error.message}")
  end

  def decoded(data) = data.empty? ? Crashed.new("the supervised process died without a report") : Marshal.load(data)

  # Drains the report while waiting, so a large one can't block the child;
  # nil once the deadline passes first.
  def collected(pid, reader, until_time)
    report = +""
    until Process.waitpid(pid, Process::WNOHANG)
      return if Process.clock_gettime(Process::CLOCK_MONOTONIC) > until_time
      report << drained(reader)
    end
    report << reader.read
  end

  def drained(reader)
    return "" unless reader.wait_readable(0.02)
    chunk = reader.read_nonblock(65_536, exception: false)
    chunk.is_a?(String) ? chunk : ""
  end

  # Kills the group (the block's forks outlive it), then reaps the leader.
  def stop(pid)
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  ensure
    begin
      Process.waitpid(pid)
    rescue Errno::ECHILD
      nil
    end
  end
end
