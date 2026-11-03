# frozen_string_literal: true

require_relative "inconclusive"

class Kimera::Execution::Shift::Doubt
  include Kimera::Execution::Shift::Inconclusive

  def initialize(test, failure, contradicted:)
    @test = test
    @failure = failure
    @contradicted = contradicted
  end

  private

  def unjudged
    "#{@test} #{evidence}, each run in a fresh process after the covering tests before it, and no other " \
      "covering test killed the mutant, so it can't be judged warm: fix the state that test depends on, " \
      "or judge the mutant with --isolated"
  end

  def evidence
    return "passed when rerun with the mutant still on" unless @contradicted
    "also failed with the mutant switched off (#{reason})"
  end

  def reason
    @failure.to_s.lines.first.to_s.strip.then { |line| line.empty? ? "no message" : line }
  end
end
