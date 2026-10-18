# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Stopwatch
  CLOCK = ->(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) { reading }

  def initialize(clock = CLOCK)
    @clock = clock
  end

  def lap
    started = @clock.call
    [yield, since(started)]
  end

  private

  def since(started) = @clock.call - started
end
