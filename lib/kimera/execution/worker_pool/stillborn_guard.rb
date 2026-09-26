# frozen_string_literal: true

require_relative "../../error"

class Kimera::Execution::WorkerPool::StillbornGuard
  def initialize(jobs)
    @jobs = jobs
    @stillborn = 0
    @progressed = false
  end

  def progress!
    @progressed = true
  end

  def track(status)
    return if @progressed
    @stillborn += 1
    abort!(status) if @stillborn > @jobs
  end

  private

  def abort!(status)
    raise(Kimera::Error, message(status))
  end

  def message(status)
    "#{@stillborn} warm workers died before reporting a result " \
      "(last exit: #{describe(status)}). The app raises during " \
      "fork or the suite aborts on load; re-run with --jobs 1 to see " \
      "the error."
  end

  def describe(status)
    [status].compact.map do |current|
      current.signaled? ? "signal #{current.termsig}" : "status #{current.exitstatus}"
    end.fetch(0, "unknown")
  end
end
