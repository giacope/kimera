# frozen_string_literal: true

require_relative "../../results/result"
require_relative "expiry"
require_relative "overrun"

Kimera::Execution::Shift::Subject =
  Data.define(:id, :file) do
    def verdict(status, **fields)
      Kimera::MutantResult.new(mutant_id: id, status: status, file: file, **fields)
    end

    def judged(outcome, tests, duration)
      fields = { duration: duration, covering_tests: tests }
      outcome ? outcome.ruling(self, fields) : verdict(:survived, **fields)
    end

    def crashed(error, limit, kind = error.class)
      message = error.message
      return verdict(:timeout, duration: limit, detail: message) if error.is_a?(Timeout::Error)
      verdict(:error, detail: "#{kind}: #{message}")
    end
  end
