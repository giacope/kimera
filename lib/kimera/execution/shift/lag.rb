# frozen_string_literal: true

require_relative "inconclusive"

class Kimera::Execution::Shift::Lag
  include Kimera::Execution::Shift::Inconclusive

  def initialize(test, failure, contradicted:)
    @test = test
    @failure = failure
    @contradicted = contradicted
  end

  private

  def unjudged
    "#{@test} #{@failure}, so the timeout can't be laid on the mutant, and no other covering test killed it: " \
      "#{@contradicted ? "fix the test, or raise" : "raise"} --soft-timeout well above the test's own time"
  end
end
