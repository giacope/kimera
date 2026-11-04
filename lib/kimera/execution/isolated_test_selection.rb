# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan; end

class Kimera::Execution::IsolatedPlan::TestSelection
  def initialize(coverage:)
    @coverage = coverage
  end

  def recorded(id)
    tests = Array(@coverage.fetch(id) { @coverage.fetch(id.to_s, []) })
    tests.empty? ? yield : tests
  end
end
