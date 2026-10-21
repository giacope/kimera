# frozen_string_literal: true

require_relative "../pace"
require_relative "finding"
require_relative "suspect"

class Kimera::Execution::Shift::Unmask
  CAP = 50
  NOTE = "failed alone in a fresh process (an earlier covering test masked it when they ran together)"

  def initialize(attempt, pace = Kimera::Execution::Pace::STILL)
    @attempt = attempt
    @pace = pace
  end

  def run(id, tests) = @pace.fastest(tests).first(CAP).lazy.filter_map { |test| alone(id, test) }.first

  private

  def alone(id, test)
    verdict = @attempt.run(id, [test])
    return if verdict.nil? || verdict.is_a?(Kimera::Execution::Shift::Doubt) || !@attempt.calm?(test)
    verdict.noted(NOTE)
  end
end
