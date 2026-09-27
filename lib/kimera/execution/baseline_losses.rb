# frozen_string_literal: true

require_relative "baseline_failure"

class Kimera::Execution::BaselineLosses
  def initialize
    @stalled = {}
    @stacks = {}
  end

  attr_reader :stacks

  def stall(test_id, stacks) = @stalled.store(test_id, stacks)

  def stalled = @stalled.keys

  def charge(test_id, reason, stacks)
    @stacks[test_id] = stacks
    failure = Kimera::Execution::BaselineFailure
    @stalled.key?(test_id) ? failure.relapsed(reason) : failure.lost(reason)
  end

  def recovered(failed) = @stalled.reject { |test_id, _stacks| failed.key?(test_id) }
end
