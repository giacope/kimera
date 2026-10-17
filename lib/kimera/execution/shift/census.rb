# frozen_string_literal: true

require_relative "../zygote"
require_relative "finding"

class Kimera::Execution::Shift::Census
  DETECTED = [Timeout::Error, Kimera::Execution::Zygote::Died, Kimera::Execution::Zygote::Raised].freeze

  def initialize(probe:, isolation:, zygote:)
    @probe = probe
    @isolation = isolation
    @zygote = zygote
  end

  def killers(id, tests, known) = tests.select { |test| known.include?(test) || detects?(id, test) }

  private

  def detects?(id, test)
    lineup = Kimera::Execution::Shift::Lineup.new(id, [test])
    !@zygote.call { @isolation.around { @probe.replay(lineup) } }["passed"]
  rescue *DETECTED
    true
  end
end
