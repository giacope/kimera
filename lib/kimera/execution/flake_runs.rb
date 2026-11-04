# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::FlakeRuns
  RANGE = 2**31

  def initialize(seed, runs, filter)
    @seed = seed
    @runs = runs
    @filter = filter
  end

  def seeds(random = Random.new)
    Array.new(Integer(@runs || 0)) { |index| @seed ? (@seed + index + 1) % RANGE : random.rand(RANGE) }
  end

  def flag(record) = Array(@filter).each { |filter| filter.flag!(record.flaky) }
end
