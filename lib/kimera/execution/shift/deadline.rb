# frozen_string_literal: true

require "timeout"
require_relative "../stopwatch"
require_relative "../time_budget"

class Kimera::Execution::Shift::Deadline
  CLOCK = Kimera::Execution::Stopwatch::CLOCK
  SILENT = -> {}

  attr_reader :budget

  class << self
    def new(seconds, clock: CLOCK, **) = super(seconds, watch: Kimera::Execution::Stopwatch.new(clock), **)
  end

  def initialize(seconds, watch:, beat: SILENT, budget: Kimera::Execution::TimeBudget::NONE)
    @seconds = seconds
    @watch = watch
    @beat = beat
    @budget = budget
  end

  def guard(testid, &)
    @beat.call
    @watch.lap { Timeout.timeout(@seconds, &) }.tap { check!(testid) }
  end

  def elapsed = @watch.last

  def overran?(testid) = @budget.exceeded?(testid, elapsed)

  private

  def check!(testid)
    return unless @seconds && elapsed >= @seconds
    raise(Timeout::Error, "soft timeout (#{@seconds}s) expired while #{testid} ran")
  end
end
