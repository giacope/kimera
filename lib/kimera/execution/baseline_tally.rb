# frozen_string_literal: true

module Kimera
  module Execution
  end
end

Kimera::Execution::BaselineTally =
  Struct.new(:coverage, :failures, :irrelevant, :timings) do
    measured = Struct.new(:coverage, :irrelevant, :recovered, :timings, keyword_init: true)
    def cover(test_id, touched, took)
      touched.each { |id| coverage[id] << test_id }
      timings[test_id] = took
    end
    define_method(:measured) do |excluded, recovered|
      measured.new(coverage: coverage, irrelevant: excluded, recovered: recovered, timings: timings)
    end
  end
