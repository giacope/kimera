# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Pace
  FILE = /\A[^\[]+/

  def initialize(timings)
    @timings = timings
  end

  def fastest(tests) = tests.sort_by.with_index { |test, index| [cost(test), index] }

  def cheapest(tests)
    files = fastest(tests).group_by { |test| test[FILE] }.values
    files.sort_by.with_index { |file, index| [file.sum { |test| cost(test) }, index] }.flatten
  end

  private

  attr_reader :timings

  def cost(test) = timings[test] || Float::INFINITY
end
