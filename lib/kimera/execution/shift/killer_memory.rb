# frozen_string_literal: true

require_relative "../pace"

class Kimera::Execution::Shift::KillerMemory
  LIMIT = 16

  def initialize(pace = Kimera::Execution::Pace.new({}), recent = [].freeze)
    @pace = pace
    @recent = recent
  end

  def order(tests)
    likely = @recent & tests
    likely + @pace.fastest(tests - likely)
  end

  def remembered(test) = self.class.new(@pace, [test, *(@recent - [test])].first(LIMIT).freeze)
end
