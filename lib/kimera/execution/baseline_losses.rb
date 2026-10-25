# frozen_string_literal: true

require_relative "baseline_failure"

Kimera::Execution::BaselineLosses =
  Struct.new(:stalled_stacks, :stacks) do
    losses = { timeout: "its worker was killed at the hard timeout (--hard-timeout) before reporting a result" }.freeze
    crash = "its worker died before reporting a result"
    alone = ", and again when rerun alone"
    def initialize(stalled_stacks = {}, stacks = {}) = super

    def stall(test_id, found) = stalled_stacks.store(test_id, found)

    def stalled = stalled_stacks.keys
    define_method(:charge) do |test_id, reason, found|
      stacks[test_id] = found
      lost = losses.fetch(reason, crash)
      stalled_stacks.key?(test_id) ? lost + alone : lost
    end
    def recovered(failed) = stalled_stacks.reject { |test_id, _stacks| failed.key?(test_id) }

    def told(test_id, message) = stacks[test_id] ? [message, stacks[test_id]] : message
  end
