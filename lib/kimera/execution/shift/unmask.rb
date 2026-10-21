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
    found = @attempt.run(id, [test])&.conclude { |_doubt| false }
    found.noted(NOTE) if found && @attempt.calm?(test)
  end
end
