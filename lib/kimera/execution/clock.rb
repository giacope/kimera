# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Clock
  def initialize(interval, id = Process::CLOCK_MONOTONIC)
    @interval = interval
    @id = id
  end

  def now(reading = Process.clock_gettime(@id)) = reading

  def pause = Kernel.sleep(@interval)
end
