# frozen_string_literal: true

require_relative "../pace"
require_relative "../zygote"
require_relative "finding"
require_relative "interruption"
require_relative "suspect"

class Kimera::Execution::Shift::Unmask
  CAP = 50
  NOTE = "failed alone in a fresh process (an earlier covering test masked it when they ran together)"

  def initialize(attempt, pace = Kimera::Execution::Pace.new({}))
    @attempt = attempt
    @pace = pace
  end

  def run(id, tests, killers)
    @pace.fastest(tests).first(CAP).each do |test|
      found, killers = alone(id, test, killers)
      return [found.first(1), killers] unless found.empty?
    end
    [[], killers]
  rescue Kimera::Execution::Zygote::Died
    raise
  rescue StandardError, ScriptError => error
    raise(Kimera::Execution::Shift::Interruption.new(error, killers))
  end

  private

  def alone(id, test, killers)
    verdicts, killers = @attempt.run(id, [test], killers)
    found = verdicts.flat_map { |verdict| verdict.conclude { |_doubt| [] } }
    [found.empty? || !@attempt.calm?(test) ? [] : found.map { |kill| kill.noted(NOTE) }, killers]
  end
end
