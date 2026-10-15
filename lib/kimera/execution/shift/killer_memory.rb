# frozen_string_literal: true

require_relative "../pace"

class Kimera::Execution::Shift::KillerMemory
  LIMIT = 16

  def initialize(pace = Kimera::Execution::Pace::STILL)
    @recent = []
    @pace = pace
  end

  def order(tests)
    likely = @recent & tests
    likely + @pace.fastest(tests - likely)
  end

  def remember(testid)
    @recent.delete(testid)
    @recent.unshift(testid)
    @recent.pop while @recent.size > LIMIT
  end
end
