# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::BaselineStall
  MAX_STACKS = 3

  def initialize(recovered, hard:, jobs:)
    @recovered = recovered
    @hard = hard
    @jobs = jobs
  end

  def to_s
    return if @recovered.empty?
    [headline, advice, *stacks].join("\n")
  end

  private

  def headline
    "kimera: #{@recovered.size} baseline test(s) hit the hard timeout (#{@hard}s) with #{@jobs} workers " \
      "running, then passed when rerun alone: #{@recovered.keys.join(", ")}"
  end

  def advice
    "  flaky under parallel load: mutants they cover can time out the same way. If they are only slow, " \
      "raise --hard-timeout; if they wait on something the workers share, give each worker its own"
  end

  def stacks
    @recovered.first(MAX_STACKS).filter_map do |test_id, stacks|
      "  #{test_id}:\n    #{stacks.gsub("\n", "\n    ")}" if stacks
    end
  end
end
