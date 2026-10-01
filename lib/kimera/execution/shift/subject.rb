# frozen_string_literal: true

require_relative "../../results/result"

Kimera::Execution::Shift::Subject =
  Data.define(:id, :file) do
    def verdict(status, **fields)
      Kimera::MutantResult.new(mutant_id: id, status: status, file: file, **fields)
    end

    def judged(outcome, tests, duration)
      fields = { duration: duration, covering_tests: tests }
      return verdict(:survived, **fields) unless outcome
      return verdict(:timeout, detail: outcome.detail, **fields) if outcome.is_a?(Kimera::Execution::Shift::Overrun)
      killed(outcome, **fields)
    end

    def crashed(error, limit)
      message = error.message
      return verdict(:timeout, duration: limit, detail: message) if error.is_a?(Timeout::Error)
      verdict(:error, detail: "#{error.class}: #{message}")
    end

    def killed(outcome, **fields)
      verdict(:killed, failing_tests: outcome.failed_ids, detail: outcome.failures.values.first, **fields)
    end
  end
