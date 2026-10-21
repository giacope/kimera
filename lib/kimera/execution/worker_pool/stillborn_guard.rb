# frozen_string_literal: true

require_relative "../../error"

class Kimera::Execution::WorkerPool::StillbornGuard
  SILENT = "; it said nothing before it died. `kimera doctor --check-baseline` loads the suite " \
    "outside the pool and prints the error."

  Seen = Struct.new(:stillborn, :progressed, keyword_init: true)

  def initialize(jobs)
    @jobs = jobs
  end

  def progress!
    seen.progressed = true
  end

  def track(status, words = nil)
    return if seen.progressed
    seen.stillborn += 1
    abort!(status, words) if seen.stillborn > @jobs
  end

  private

  def seen = @_seen ||= Seen.new(stillborn: 0, progressed: false)

  def abort!(status, words)
    raise(Kimera::Error, message(status) + (words ? ". The last one died of:\n#{words}" : SILENT))
  end

  def message(status)
    "#{seen.stillborn} warm workers died before reporting a result " \
      "(last exit: #{describe(status)}). The app raises during " \
      "fork or the suite aborts on load"
  end

  def describe(status)
    [status].compact.map do |current|
      current.signaled? ? "signal #{current.termsig}" : "status #{current.exitstatus}"
    end.fetch(0, "unknown")
  end
end
