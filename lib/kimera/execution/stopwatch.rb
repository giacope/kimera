# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Stopwatch
  CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  attr_reader :last

  def initialize(clock = CLOCK)
    @clock = clock
  end

  def lap
    started = @clock.call
    yield.tap { @last = since(started) }
  end

  private

  def since(started) = @clock.call - started
end
