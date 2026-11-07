# frozen_string_literal: true

module HeapWalks
  def walks(&)
    count = 0
    trace = TracePoint.new(:c_call) { |call| count += 1 if call.method_id == :each_object && call.self == ObjectSpace }
    trace.enable(&)
    count
  end
end

RSpec.configure { |config| config.include(HeapWalks) }
