# frozen_string_literal: true

require "timeout"

class Kimera::Execution::Shift::Deadline
  CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  SILENT = -> {}

  def initialize(seconds, clock: CLOCK, beat: SILENT)
    @seconds = seconds
    @clock = clock
    @beat = beat
  end

  def guard(testid, &)
    @beat.call
    started = @clock.call
    Timeout.timeout(@seconds, &).tap { check!(testid, started) }
  end

  private

  def check!(testid, started)
    return unless @seconds && @clock.call - started >= @seconds
    raise(Timeout::Error, "soft timeout (#{@seconds}s) expired while #{testid} ran")
  end
end
