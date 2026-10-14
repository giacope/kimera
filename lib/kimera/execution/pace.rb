# frozen_string_literal: true

module Kimera
  module Execution
  end
end

Kimera::Execution::Pace =
  Data.define(:timings) do
    def fastest(tests) = tests.sort_by.with_index { |test, index| [timings[test] || Float::INFINITY, index] }
  end

Kimera::Execution::Pace::STILL = Kimera::Execution::Pace.new({}.freeze)
