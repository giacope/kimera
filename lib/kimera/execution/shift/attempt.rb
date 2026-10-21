# frozen_string_literal: true

require_relative "deadline"
require_relative "expiry"
require_relative "finding"
require_relative "probe"
require_relative "suspect"

class Kimera::Execution::Shift::Attempt
  CLEAR = 0.5

  def initialize(probe:, isolation:, killers:, zygote:)
    @probe = probe
    @isolation = isolation
    @killers = killers
    @zygote = zygote
  end

  def run(id, tests) = hunt(Kimera::Execution::Shift::Lineup.new(id, @killers.order(tests)), [])

  private

  def hunt(lineup, doubts)
    found = fresh { @probe.sweep(lineup) }
    return doubts.first&.final unless found
    finding = Kimera::Execution::Shift::Finding.new(lineup, found)
    settle(finding, doubts, judge(finding))
  end

  def settle(finding, doubts, verdict)
    return verdict if verdict && !verdict.is_a?(Kimera::Execution::Shift::Suspect)
    hunt(finding.onward, doubts + [verdict].compact)
  end

  def judge(finding)
    return expired(finding) if finding.expired?
    finding.overran? ? lagged(finding) : failed(finding)
  end

  def expired(finding)
    calm = replay(finding.calm)
    clear?(calm) ? finding.stall(calm) : finding.crawl(calm)
  end

  def clear?(calm) = calm["passed"] && calm.fetch("elapsed") < calm.fetch("limit") * CLEAR

  def failed(finding)
    return finding.kill(finding.found, @killers) if finding.first?
    solo = replay(finding.solo)
    solo["passed"] ? retrace(finding) : finding.kill(solo, @killers)
  end

  def retrace(finding)
    control = replay(finding.control)
    control["passed"] ? confirm(finding) : finding.refuted(control)
  end

  def confirm(finding)
    again = replay(finding.again)
    again["passed"] ? finding.doubted : finding.kill(again, @killers)
  end

  def lagged(finding)
    calm = replay(finding.calm)
    return unless calm["passed"] && !calm["overran"]
    again = replay(finding.solo)
    finding.overrun(calm, again, @probe.deadline.budget) if again["overran"]
  end

  def replay(lineup) = fresh { @probe.replay(lineup) }

  def fresh(&) = @zygote.call { @isolation.around(&) }
end
