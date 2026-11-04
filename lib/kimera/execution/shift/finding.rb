# frozen_string_literal: true

require_relative "failure"
require_relative "hang"
require_relative "slowdown"

class Kimera::Execution::Shift::Finding
  def initialize(id, tests, found)
    @id = id
    @tests = tests
    @found = found
  end

  def onward = Kimera::Execution::Shift::Lineup.new(@id, @tests.drop(index + 1))

  def judged(attempt, explainer)
    return Kimera::Execution::Shift::Hang.new(test, @found).judged(attempt) if kind?("expired")
    return Kimera::Execution::Shift::Slowdown.new(@id, test, @found).judged(attempt, explainer) if kind?("overran")
    Kimera::Execution::Shift::Failure.new(@id, @tests.first(index + 1), @found).judged(attempt)
  end

  private

  def kind?(kind) = @found.fetch("kind") == kind

  def test = @tests.fetch(index)

  def index = @found.fetch("index")
end
