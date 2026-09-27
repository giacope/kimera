# frozen_string_literal: true

require_relative "../../results/result"

Kimera::Execution::Shift::Subject =
  Data.define(:id, :file) do
    def verdict(status, **fields)
      Kimera::MutantResult.new(mutant_id: id, status: status, file: file, **fields)
    end

    def judged(outcome, tests, duration)
      return verdict(:survived, duration: duration, covering_tests: tests) unless outcome
      killed(outcome, duration: duration, covering_tests: tests)
    end

    def killed(outcome, **fields)
      verdict(:killed, failing_tests: outcome.failed_ids, detail: outcome.failures.values.first, **fields)
    end
  end
