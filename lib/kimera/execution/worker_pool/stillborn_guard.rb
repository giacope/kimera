# frozen_string_literal: true

require_relative "../../error"

class Kimera::Execution::WorkerPool::StillbornGuard
  SILENT = "; it said nothing before it died. `kimera doctor --check-baseline` loads the suite " \
    "outside the pool and prints the error."

  Seen =
    Struct.new(:stillborn, :progressed, keyword_init: true) do
      private(*members)
      def progress!
        self.progressed = true
      end

      def track(jobs)
        return if progressed
        self.stillborn += 1
        yield(stillborn) if stillborn > jobs
      end
    end

  def initialize(jobs, seen = Seen.new(stillborn: 0, progressed: false))
    @jobs = jobs
    @seen = seen
  end

  def progress!
    @seen.progress!
  end

  def track(status, words = nil)
    @seen.track(@jobs) { |stillborn| abort!(status, words, stillborn) }
  end

  private

  def abort!(status, words, stillborn)
    raise(Kimera::Error, message(status, stillborn) + (words ? ". The last one died of:\n#{words}" : SILENT))
  end

  def message(status, stillborn)
    "#{stillborn} warm workers died before reporting a result " \
      "(last exit: #{describe(status)}). The app raises during " \
      "fork or the suite aborts on load"
  end

  def describe(status)
    [status].compact.map do |current|
      current.signaled? ? "signal #{current.termsig}" : "status #{current.exitstatus}"
    end.fetch(0, "unknown")
  end
end
