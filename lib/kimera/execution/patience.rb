# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Patience
  FACTOR = 3.0
  SLACK = 1.0

  attr_reader :seconds

  def initialize(seconds, timings: {}, ceiling: nil)
    @seconds = seconds
    @timings = timings
    @ceiling = ceiling
  end

  def limit(test)
    base = @seconds && @timings[test]
    return @seconds unless base
    raised = (base * FACTOR) + SLACK
    [@seconds, @ceiling ? [raised, @ceiling].min : raised].max
  end

  def longest(tests) = tests.map { |test| limit(test) }.max || @seconds
end
