# frozen_string_literal: true

require "timeout"

class Kimera::Execution::Shift::Attempt
  def initialize(adapter:, isolation:, killers:, timeout:)
    @adapter = adapter
    @isolation = isolation
    @killers = killers
    @timeout = timeout
  end

  def run(id, tests)
    timeout { @isolation.around { attempt(id, tests) } }
  end

  private

  def attempt(id, tests)
    @killers.order(tests).lazy.map { |testid| kill(id, testid) }.find { |outcome| outcome }
  end

  def kill(id, testid)
    Kimera::Runtime.active = id
    outcome = @adapter.run([testid])
    return if outcome.passed?
    @killers.remember(testid)
    outcome
  end

  def timeout(&)
    Timeout.timeout(@timeout, &)
  end
end
