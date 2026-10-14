# frozen_string_literal: true

class Kimera::Execution::Shift::KillerMemory
  LIMIT = 16

  def initialize(timings = {})
    @recent = []
    @timings = timings
  end

  def order(tests)
    likely = @recent & tests
    likely + fastest(tests - likely)
  end

  def remember(testid)
    @recent.delete(testid)
    @recent.unshift(testid)
    @recent.pop while @recent.size > LIMIT
  end

  private

  def fastest(tests) = tests.sort_by.with_index { |test, index| [@timings[test] || Float::INFINITY, index] }
end
