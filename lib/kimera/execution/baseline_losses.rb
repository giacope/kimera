# frozen_string_literal: true

require_relative "baseline_failure"

class Kimera::Execution::BaselineLosses
  LOSSES = { timeout: "its worker was killed at the hard timeout (--hard-timeout) before reporting a result" }.freeze
  CRASH = "its worker died before reporting a result"
  ALONE = ", and again when rerun alone"

  def initialize
    @stalled = {}
    @stacks = {}
  end

  attr_reader :stacks

  def stall(test_id, stacks) = @stalled.store(test_id, stacks)

  def stalled = @stalled.keys

  def charge(test_id, reason, stacks)
    @stacks[test_id] = stacks
    lost = LOSSES.fetch(reason, CRASH)
    @stalled.key?(test_id) ? lost + ALONE : lost
  end

  def recovered(failed) = @stalled.reject { |test_id, _stacks| failed.key?(test_id) }
end
