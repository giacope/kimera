# frozen_string_literal: true

require "tempfile"
require_relative "child_process"

class Kimera::Execution::SuiteCapture
  include Kimera::Execution::ChildProcess

  POLL = 0.2
  TICKS = 150
  OVERDUE = "the suite did not exit within %s s (a hook, or a parallel worker, that never returns?); " \
    "run it yourself to see where it stops"

  Overdue = Data.define(:limit) { def success? = false }

  def initialize(errors = $stderr)
    @errors = errors
  end

  def call(env, *command, chdir:, limit: nil)
    Tempfile.create("kimera-suite") do |log|
      pid = Process.spawn(env, *command, chdir: chdir, in: File::NULL, out: log, err: log, pgroup: true)
      status = stopping(pid) { limit ? waited(pid, limit, log) : Process.wait2(pid).last.tap { signal(-pid) } }
      [File.read(log.path, encoding: Encoding::UTF_8).scrub, status]
    end
  end

  private

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
