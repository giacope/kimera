# frozen_string_literal: true

require_relative "deadline"
require_relative "suspect"
require_relative "trial"

class Kimera::Execution::Shift::Attempt
  def initialize(adapter:, isolation:, killers:, deadline:)
    @adapter = adapter
    @isolation = isolation
    @killers = killers
    @deadline = deadline
  end

  def run(id, tests, mode = :warm)
    @deadline.guard { @isolation.around { __send__(mode, verdicts(id, tests)) } }
  end

  private

  def verdicts(id, tests) = @killers.order(tests).lazy.filter_map { |testid| kill(id, testid) }

  def warm(verdicts) = verdicts.first

  def recheck(verdicts)
    doubts = []
    verdicts.find { |verdict| decisive?(verdict, doubts) } || doubts.first&.final
  end

  def decisive?(verdict, doubts)
    return true unless verdict.is_a?(Kimera::Execution::Shift::Suspect)
    doubts << verdict
    false
  end

  def kill(id, testid)
    Kimera::Execution::Shift::Trial.new(@adapter, id, testid).verdict(@deadline) { @killers.remember(testid) }
  end
end
