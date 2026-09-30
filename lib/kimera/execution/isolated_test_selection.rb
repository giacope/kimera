# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan; end

class Kimera::Execution::IsolatedPlan::TestSelection
  attr_reader :all

  def initialize(all_tests:, coverage:)
    @all = all_tests
    @coverage = coverage
  end

  def recorded(id)
    return @all unless @coverage
    tests = @coverage[id] || @coverage[id.to_s]
    tests unless Array(tests).empty?
  end
end
