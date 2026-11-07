# frozen_string_literal: true

require_relative "baseline_stall"

module Kimera
  module Execution
  end
end

Kimera::Execution::BaselineTally =
  Struct.new(:coverage, :failures, :irrelevant, :timings, :messages) do
    private(*members)
    def cover(test_id, touched, took)
      touched.each { |id| coverage[id] << test_id }
      timings[test_id] = took
    end

    def charge(test_id, message)
      messages[test_id] = message
      failures << test_id
    end

    def excuse(test_id, message)
      messages[test_id] = message
      irrelevant << test_id
    end

    def failing
      yield(failures, messages) unless failures.empty?
    end

    def measured(losses)
      excluded = irrelevant.to_h { |test_id| [test_id, messages[test_id]] }
      Kimera::Execution::BaselineTally::Measured.new(
        coverage: coverage, irrelevant: excluded, recovered: losses.recovered(messages), timings: timings
      )
    end
  end

Kimera::Execution::BaselineTally::Measured =
  Data.define(:coverage, :irrelevant, :recovered, :timings) do
    private(*members)
    def screened(screen) = screen.call(irrelevant)

    def stall(**) = Kimera::Execution::BaselineStall.new(recovered, **).to_s
  end
