# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::TimeBudget
  FACTOR = 10.0
  SLACK = 1.0

  def initialize(baselines, factor: FACTOR, slack: SLACK)
    @baselines = baselines
    @factor = factor
    @slack = slack
  end

  def exceeded?(test, seconds)
    cap = limit(test)
    cap ? seconds > cap : false
  end

  def explain(test, runs, control)
    "#{test} ran past its relative time budget with the mutant on (#{laps(runs)}; budget #{seconds(limit(test))} = " \
      "baseline #{seconds(@baselines.fetch(test), 3)} × #{@factor} + #{@slack}s), " \
      "and in #{seconds(control, 3)} with it off"
  end

  private

  def limit(test)
    base = @baselines[test]
    base && ((base * @factor) + @slack)
  end

  def laps(runs) = runs.map { |run| seconds(run) }.join(", then ")

  def seconds(value, digits = 2) = "#{value.round(digits)}s"
end

Kimera::Execution::TimeBudget::NONE = Kimera::Execution::TimeBudget.new({}.freeze)
