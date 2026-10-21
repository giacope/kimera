# frozen_string_literal: true

require "timeout"
require_relative "../stopwatch"
require_relative "../time_budget"
require_relative "../patience"

class Kimera::Execution::Shift::Deadline
  CLOCK = Kimera::Execution::Stopwatch::CLOCK
  SILENT = -> {}

  attr_reader :budget

  class << self
    def build(seconds, clock: CLOCK, patience: Kimera::Execution::Patience.new(seconds), **)
      new(patience, watch: Kimera::Execution::Stopwatch.new(clock), **)
    end
  end

  def initialize(patience, watch:, beat: SILENT, budget: Kimera::Execution::TimeBudget::NONE)
    @patience = patience
    @watch = watch
    @beat = beat
    @budget = budget
  end

  def limit(testid) = @patience.limit(testid)

  def guard(testid, &)
    @beat.call
    seconds = limit(testid)
    @watch.lap { Timeout.timeout(seconds, &) }.tap { |_value, elapsed| check!(testid, elapsed, seconds) }
  end

  def overran?(testid, elapsed) = @budget.exceeded?(testid, elapsed)

  private

  def check!(testid, elapsed, seconds)
    return unless seconds && elapsed >= seconds
    raise(Timeout::Error, "soft timeout (#{seconds}s) expired while #{testid} ran")
  end
end
