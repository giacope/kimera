# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Patience
  FACTOR = 3.0
  SLACK = 1.0
  private_constant(:FACTOR, :SLACK)

  attr_reader :seconds

  def initialize(seconds, timings: {}, hard: Float::INFINITY)
    @seconds = seconds
    @timings = timings
    @hard = hard
  end

  def limit(test)
    base = @seconds && @timings[test]
    return @seconds unless base
    raised = (base * FACTOR) + SLACK
    [@seconds, raised.clamp(..(@hard - SLACK))].max
  end

  def longest(tests) = tests.map { |test| limit(test) }.max || @seconds
end
