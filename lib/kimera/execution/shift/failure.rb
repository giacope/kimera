# frozen_string_literal: true

require_relative "doubt"
require_relative "kill"
require_relative "suspect"

class Kimera::Execution::Shift::Failure
  def initialize(id, through, found)
    @id = id
    @through = through
    @found = found
  end

  def judged(attempt)
    return [kill(@found)] if @through.size == 1
    solo = attempt.replayed(lineup(@id, [test]))
    solo["passed"] ? retrace(attempt) : [kill(solo)]
  end

  private

  def test = @through.fetch(-1)

  def lineup(active, tests) = Kimera::Execution::Shift::Lineup.new(active, tests)

  def retrace(attempt)
    control = attempt.replayed(lineup(nil, @through))
    control["passed"] ? confirm(attempt) : [suspect(control.fetch("failures")[test], contradicted: true)]
  end

  def confirm(attempt)
    again = attempt.replayed(lineup(@id, @through))
    [again["passed"] ? suspect(@found.fetch("failures")[test], contradicted: false) : kill(again)]
  end

  def kill(result) = Kimera::Execution::Shift::Kill.new(test, result["failed_ids"], result["failures"])

  def suspect(failure, contradicted:)
    Kimera::Execution::Shift::Suspect.new(Kimera::Execution::Shift::Doubt.new(test, failure, contradicted:))
  end
end
