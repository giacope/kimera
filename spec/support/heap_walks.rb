# frozen_string_literal: true

# How often the block walks the object space, seen through a TracePoint on
# ObjectSpace.each_object as the block runs.
module HeapWalks
  def walks(&)
    count = 0
    trace = TracePoint.new(:c_call) { |call| count += 1 if call.method_id == :each_object && call.self == ObjectSpace }
    trace.enable(&)
    count
  end
end

RSpec.configure { |config| config.include(HeapWalks) }
