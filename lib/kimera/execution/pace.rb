# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Pace
  def initialize(timings)
    @timings = timings
  end

  def fastest(tests) = tests.sort_by.with_index { |test, index| [timings[test] || Float::INFINITY, index] }

  private

  attr_reader :timings
end
