# frozen_string_literal: true

require "timeout"

class Kimera::Execution::Shift::Deadline
  CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  def initialize(seconds, clock: CLOCK)
    @seconds = seconds
    @clock = clock
  end

  def guard(&)
    @started = @clock.call
    Timeout.timeout(@seconds, &)
  end

  def check!(testid)
    return unless @seconds && @clock.call - @started >= @seconds
    raise(Timeout::Error, "soft timeout (#{@seconds}s) expired while #{testid} ran")
  end
end
