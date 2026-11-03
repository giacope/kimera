# frozen_string_literal: true

class Kimera::Execution::WorkerPool::Listeners
  def initialize(resolve:, lost:, trace:)
    @resolve = resolve
    @lost = lost
    @trace = trace
  end

  def resolved(message) = @resolve.call(message)

  def lost(id, reason, stacks) = @lost.call(id, reason, stacks)

  def traced(slot, id)
    @trace&.call(slot, id)
    self
  end
end
