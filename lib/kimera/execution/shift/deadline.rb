# frozen_string_literal: true

require "timeout"
require_relative "../stopwatch"
require_relative "../time_budget"

class Kimera::Execution::Shift::Deadline
  CLOCK = Kimera::Execution::Stopwatch::CLOCK
  SILENT = -> {}

  attr_reader :budget, :seconds

  class << self
    def build(seconds, clock: CLOCK, **) = new(seconds, watch: Kimera::Execution::Stopwatch.new(clock), **)
  end

  def initialize(seconds, watch:, beat: SILENT, budget: Kimera::Execution::TimeBudget::NONE)
    @seconds = seconds
    @watch = watch
    @beat = beat
    @budget = budget
  end

  def guard(testid, &)
    @beat.call
    @watch.lap { Timeout.timeout(@seconds, &) }.tap { |_value, elapsed| check!(testid, elapsed) }
  end

  def overran?(testid, elapsed) = @budget.exceeded?(testid, elapsed)

  private

  def check!(testid, elapsed)
    return unless @seconds && elapsed >= @seconds
    raise(Timeout::Error, "soft timeout (#{@seconds}s) expired while #{testid} ran")
  end
end
