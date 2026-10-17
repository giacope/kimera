# frozen_string_literal: true

require "timeout"

Kimera::Execution::Shift::Probe =
  Data.define(:adapter, :deadline) do
    def sweep(lineup)
      active = lineup.active
      lineup.tests.each_with_index.lazy.filter_map { |test, index| finding(test, *run(active, test), index) }.first
    end

    def replay(lineup)
      active = lineup.active
      lineup.tests.map { |test| report(test, *run(active, test)) }.last
    end

    def finding(test, outcome, elapsed, index)
      return report(test, outcome, elapsed).merge("index" => index, "kind" => "failed") unless outcome.passed?
      report(test, outcome, elapsed).merge("index" => index, "kind" => "overran") if deadline.overran?(test, elapsed)
    end

    def report(test, outcome, elapsed)
      { "passed" => outcome.passed?, "failed_ids" => outcome.failed_ids, "failures" => outcome.failures }
        .merge("elapsed" => elapsed, "overran" => deadline.overran?(test, elapsed))
    end

    def run(active, test)
      Kimera::RUNTIME.active = active
      deadline.guard(test) { adapter.run([test]) }
    end
  end
