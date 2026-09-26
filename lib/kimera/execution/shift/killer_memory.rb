# frozen_string_literal: true

class Kimera::Execution::Shift::KillerMemory
  LIMIT = 16

  def initialize
    @recent = []
  end

  def order(tests)
    likely = @recent & tests
    likely + (tests - likely)
  end

  def remember(testid)
    @recent.delete(testid)
    @recent.unshift(testid)
    @recent.pop while @recent.size > LIMIT
  end
end
