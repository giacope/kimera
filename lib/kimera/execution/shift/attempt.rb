# frozen_string_literal: true

require_relative "deadline"
require_relative "expiry"
require_relative "lineup"
require_relative "probe"

class Kimera::Execution::Shift::Attempt
  def initialize(probe:, isolation:, zygote:)
    @probe = probe
    @isolation = isolation
    @zygote = zygote
  end

  def run(id, tests, killers)
    verdicts = hunt(Kimera::Execution::Shift::Lineup.new(id, killers.order(tests)), [])
    [verdicts, verdicts.reduce(killers) { |known, verdict| verdict.taught(known) }]
  end

  def calm?(test) = replayed(Kimera::Execution::Shift::Lineup.new(nil, [test]))["passed"]

  def replayed(lineup) = fresh { @probe.replay(lineup) }

  private

  def hunt(lineup, doubts)
    found = fresh { @probe.sweep(lineup) }
    return doubts.first(1).map(&:final) if found.empty?
    finding = lineup.found(found.fetch(0))
    settle(finding, doubts, finding.judged(self, @probe))
  end

  def settle(finding, doubts, verdicts)
    return hunt(finding.onward, doubts) if verdicts.empty?
    verdicts.fetch(0).conclude { |suspect| hunt(finding.onward, doubts + [suspect]) }
  end

  def fresh(&) = @zygote.call { @isolation.around(&) }
end
