# frozen_string_literal: true

require_relative "deadline"
require_relative "finding"
require_relative "overrun"
require_relative "probe"
require_relative "suspect"

class Kimera::Execution::Shift::Attempt
  def initialize(probe:, isolation:, killers:, zygote:)
    @probe = probe
    @isolation = isolation
    @killers = killers
    @zygote = zygote
  end

  def run(id, tests) = hunt(id, @killers.order(tests), [])

  private

  def hunt(id, tests, doubts)
    found = fresh { @probe.sweep(id, tests) }
    return doubts.first&.final unless found
    finding = Kimera::Execution::Shift::Finding.new(tests, found)
    settle(id, finding, doubts, judge(id, finding))
  end

  def settle(id, finding, doubts, verdict)
    return verdict if verdict && !verdict.is_a?(Kimera::Execution::Shift::Suspect)
    hunt(id, finding.rest, doubts + [verdict].compact)
  end

  def judge(id, finding) = finding.overran? ? lagged(id, finding) : failed(id, finding)

  def failed(id, finding)
    solo = replay(id, [finding.test])
    return kill(finding.test, solo) unless solo["passed"]
    control = replay(nil, finding.through)
    control["passed"] ? confirm(id, finding) : finding.refuted(id, control)
  end

  def confirm(id, finding)
    again = replay(id, finding.through)
    again["passed"] ? finding.doubted(id) : kill(finding.test, again)
  end

  def lagged(id, finding)
    calm = replay(nil, [finding.test])
    return unless calm["passed"] && !calm["overran"]
    again = replay(id, [finding.test])
    overrun(finding, calm, again) if again["overran"]
  end

  def overrun(finding, calm, again)
    runs = [finding.elapsed, again["elapsed"]]
    Kimera::Execution::Shift::Overrun.new(finding.test, runs, calm["elapsed"], @probe.deadline.budget)
  end

  def kill(test, result)
    @killers.remember(test)
    Kimera::Execution::Shift::Finding::Kill.new(result["failed_ids"], result["failures"])
  end

  def replay(active, tests) = fresh { @probe.replay(active, tests) }

  def fresh(&) = @zygote.call { @isolation.around(&) }
end
