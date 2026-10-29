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

  def calm?(test) = replay(Kimera::Execution::Shift::Lineup.new(nil, [test]))["passed"]

  private

  def hunt(lineup, doubts)
    found = fresh { @probe.sweep(lineup) }
    return doubts.first(1).map(&:final) if found.empty?
    finding = Kimera::Execution::Shift::Finding.new(lineup, found.fetch(0))
    settle(finding, doubts, judge(finding))
  end

  def settle(finding, doubts, verdicts)
    return hunt(finding.onward, doubts) if verdicts.empty?
    verdicts.fetch(0).conclude { |suspect| hunt(finding.onward, doubts + [suspect]) }
  end

  def judge(finding)
    return expired(finding) if finding.expired?
    finding.overran? ? lagged(finding) : failed(finding)
  end

  def expired(finding)
    calm = replay(finding.calm)
    [clear?(calm) ? finding.stall(calm) : finding.crawl(calm)]
  end

  def clear?(calm) = calm["passed"] && calm.fetch("elapsed") < calm.fetch("limit") * CLEAR

  def failed(finding)
    return [killed(finding, finding.found)] if finding.first?
    solo = replay(finding.solo)
    solo["passed"] ? retrace(finding) : [killed(finding, solo)]
  end

  def killed(finding, result)
    @killers.remember(finding.test)
    finding.kill(result)
  end

  def retrace(finding)
    control = replay(finding.control)
    control["passed"] ? confirm(finding) : [finding.refuted(control)]
  end

  def confirm(finding)
    again = replay(finding.again)
    [again["passed"] ? finding.doubted : killed(finding, again)]
  end

  def lagged(finding)
    calm = replay(finding.calm)
    return [] unless calm["passed"] && !calm["overran"]
    again = replay(finding.solo)
    again["overran"] ? [finding.overrun(calm, again, @probe)] : []
  end

  def replay(lineup) = fresh { @probe.replay(lineup) }

  def fresh(&) = @zygote.call { @isolation.around(&) }
end
