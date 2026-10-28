# frozen_string_literal: true

require "tempfile"
require_relative "child_process"
require_relative "suite_env"

class Kimera::Execution::SuiteCapture
  include Kimera::Execution::ChildProcess

  POLL = 0.2
  TICKS = 150
  OVERDUE = "the suite did not exit within %s s (a hook, or a parallel worker, that never returns?); " \
    "run it yourself to see where it stops"

  Overdue = Data.define(:limit) { def success? = false }

  def initialize(errors = $stderr, env = Kimera::Execution::SuiteEnv.new)
    @errors = errors
    @env = env
  end

  def call(*spawned, chdir:) = captured(spawned, chdir) { |pid| Process.wait2(pid).last.tap { signal(-pid) } }

  def timed(*spawned, chdir:, limit:) = captured(spawned, chdir) { |pid, log| waited(pid, limit, log) }

  private

  def captured(spawned, chdir)
    Tempfile.create("kimera-suite") do |log|
      pid = Process.spawn(@env.to_h, *spawned, chdir: chdir, in: File::NULL, out: log, err: log, pgroup: true)
      status = stopping(pid) { yield(pid, log) }
      [File.read(log.path, encoding: Encoding::UTF_8).scrub, status]
    end
  end

  def stopping(pid)
    yield
  rescue SignalException
    stop(pid)
    raise
  end

  def waited(pid, limit, log)
    started = now
    (1..).each do |poll|
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status.tap { signal(-pid) } if status
      elapsed = now - started
      return overdue(pid, limit, log) if elapsed > limit
      sleep(POLL)
      tick(elapsed) if (poll % TICKS).zero?
    end
  end

  def tick(elapsed) = @errors.puts("kimera: the suite is still running (#{elapsed.round} s)…")

  def overdue(pid, limit, log)
    stop(-pid)
    log.write("\n#{format(OVERDUE, limit)}\n")
    log.flush
    Overdue.new(limit)
  end
end

Kimera::Execution::SUITE = Kimera::Execution::SuiteCapture.new
