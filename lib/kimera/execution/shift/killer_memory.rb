# frozen_string_literal: true

require_relative "../pace"

Kimera::Execution::Shift::KillerMemory =
  Struct.new(:pace, :recent) do
    limit = 16
    def initialize(pace = Kimera::Execution::Pace::STILL, recent = []) = super

    def order(tests)
      likely = recent & tests
      likely + pace.fastest(tests - likely)
    end
    define_method(:remember) do |testid|
      recent.delete(testid)
      recent.unshift(testid)
      recent.pop while recent.size > limit
    end
  end
