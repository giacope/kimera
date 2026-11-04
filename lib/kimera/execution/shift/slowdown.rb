# frozen_string_literal: true

require_relative "overrun"

class Kimera::Execution::Shift::Slowdown
  def initialize(id, test, found)
    @id = id
    @test = test
    @found = found
  end

  def judged(attempt, explainer)
    calm = attempt.replayed(lineup(nil))
    return [] unless calm["passed"] && !calm["overran"]
    again = attempt.replayed(lineup(@id))
    again["overran"] ? [overrun(calm, again, explainer)] : []
  end

  private

  def lineup(active) = Kimera::Execution::Shift::Lineup.new(active, [@test])

  def overrun(calm, again, explainer)
    runs = [@found.fetch("elapsed"), again["elapsed"]]
    Kimera::Execution::Shift::Overrun.new(@test, runs, calm["elapsed"], explainer)
  end
end
