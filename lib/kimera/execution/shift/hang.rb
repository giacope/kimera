# frozen_string_literal: true

require_relative "lag"
require_relative "stall"
require_relative "suspect"

class Kimera::Execution::Shift::Hang
  CLEAR = 0.5

  def initialize(test, found)
    @test = test
    @found = found
  end

  def judged(attempt)
    calm = attempt.replayed(Kimera::Execution::Shift::Lineup.new(nil, [@test]))
    [clear?(calm) ? stall(calm) : crawl(calm)]
  end

  private

  def clear?(calm) = calm["passed"] && calm.fetch("elapsed") < calm.fetch("limit") * CLEAR

  def stall(calm)
    Kimera::Execution::Shift::Stall.new(@test, @found.fetch("failures").fetch(@test), calm.fetch("elapsed"))
  end

  def crawl(calm)
    doubt = Kimera::Execution::Shift::Lag.new(@test, lag(calm), contradicted: !calm["passed"])
    Kimera::Execution::Shift::Suspect.new(doubt)
  end

  def lag(calm)
    past = "ran past its soft timeout (#{calm["limit"]}s) with the mutant on"
    return "#{past} and with it off" if calm["expired"]
    return "#{past}, and failed with it off" unless calm["passed"]
    "#{past}, and took #{calm.fetch("elapsed").round(2)}s with it off"
  end
end
