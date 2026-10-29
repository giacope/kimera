# frozen_string_literal: true

require "timeout"
require_relative "expiry"

Kimera::Execution::Shift::Probe =
  Data.define(:adapter, :deadline) do
    def sweep(lineup)
      active = lineup.active
      lineup.tests.each_with_index.lazy.flat_map { |test, index| finding(test, *run(active, test), index) }.first(1)
    end

    def replay(lineup)
      active = lineup.active
      lineup.tests.map { |test| report(test, *run(active, test)) }.fetch(-1)
    end

    def finding(test, outcome, elapsed, index)
      kind = outcome.expired? ? "expired" : "failed"
      return [report(test, outcome, elapsed).merge("index" => index, "kind" => kind)] unless outcome.passed?
      return [] unless deadline.overran?(test, elapsed)
      [report(test, outcome, elapsed).merge("index" => index, "kind" => "overran")]
    end

    def report(test, outcome, elapsed)
      { "passed" => outcome.passed?, "failed_ids" => outcome.failed_ids, "failures" => outcome.failures }
        .merge("elapsed" => elapsed, "overran" => deadline.overran?(test, elapsed), "expired" => outcome.expired?)
        .merge("limit" => deadline.limit(test))
    end

    def run(active, test)
      Kimera::RUNTIME.active = active
      deadline.guard(test) { adapter.run([test]) }
    rescue Timeout::Error => error
      [Kimera::Execution::Shift::Expiry.new(test: test, message: error.message), deadline.limit(test)]
    end
  end
