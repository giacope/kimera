# frozen_string_literal: true

require "yaml"

module Supervised
  class Overdue < StandardError; end

  GRACE = 2

  Crashed = Struct.new(:detail)

  module_function

  def run(deadline:, &)
    reader, writer = IO.pipe
    pid = fork { serve(reader, writer, &) }
    writer.close
    report = collected(pid, reader, Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline)
    settle(pid) unless report
    stop(pid)
    raise(Overdue, "still running after #{deadline}s; killed its process group") unless report
    decoded(report)
  ensure
    reader.close
  end

  def serve(reader, writer, &)
    reader.close
    Process.setpgid(0, 0)
    writer.write(YAML.dump(outcome(&)))
    writer.close
    exit!(0)
  end

  def outcome
    yield
  rescue StandardError, ScriptError => error
    Crashed.new("#{error.class}: #{error.message}")
  end

  def decoded(data)
    return Crashed.new("the supervised process died without a report") if data.empty?
    YAML.safe_load(data, permitted_classes: [Symbol, Crashed], aliases: true)
  end

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

  def settle(pid)
    Process.kill("TERM", pid)
    until_time = now + GRACE
    sleep(0.02) until Process.waitpid(pid, Process::WNOHANG) || now > until_time
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
