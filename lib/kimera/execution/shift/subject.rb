# frozen_string_literal: true

require_relative "../../results/result"
require_relative "../fault"
require_relative "expiry"
require_relative "overrun"

using Kimera::Execution::Fault

class Kimera::Execution::Shift::Subject
  def initialize(id, file)
    @id = id
    @file = file
  end

  def verdict(status, **fields)
    Kimera::MutantResult.new(mutant_id: @id, status: status, file: @file, **fields)
  end

  def judged(outcomes, tests, duration)
    fields = { duration: duration, covering_tests: tests }
    outcomes.map { |outcome| outcome.ruling(self, fields) }.fetch(0) { verdict(:survived, **fields) }
  end

  def crashed(error, limit)
    return verdict(:timeout, duration: limit, detail: error.message) if error.is_a?(Timeout::Error)
    verdict(:error, detail: error.headline)
  end
end
