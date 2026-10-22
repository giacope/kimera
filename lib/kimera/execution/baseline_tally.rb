# frozen_string_literal: true

module Kimera
  module Execution
  end
end

Kimera::Execution::BaselineTally =
  Struct.new(:coverage, :failures, :irrelevant, :timings, :messages) do
    def cover(test_id, touched, took)
      touched.each { |id| coverage[id] << test_id }
      timings[test_id] = took
    end

    def measured(recovered)
      excluded = irrelevant.to_h { |test_id| [test_id, messages[test_id]] }
      Kimera::Execution::BaselineTally::Measured.new(
        coverage: coverage, irrelevant: excluded, recovered: recovered, timings: timings
      )
    end
  end

# What the baseline measured: the tests covering each mutant, the failing
# tests that cover none (with their messages), the tests a rerun recovered,
# and how long each test took.
Kimera::Execution::BaselineTally::Measured =
  Struct.new(:coverage, :irrelevant, :recovered, :timings, keyword_init: true)
