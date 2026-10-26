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

Kimera::Execution::BaselineTally::Measured =
  Struct.new(:coverage, :irrelevant, :recovered, :timings, keyword_init: true)
