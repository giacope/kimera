# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Sweep
  def initialize(ids, lock, tick)
    @ids = ids
    @lock = lock
    @tick = tick
  end

  def results = @_results ||= []

  def each(&) = @ids.each(&)

  def drain
    while (id = queue.pop(timeout: 0))
      yield(id)
    end
  end

  def record(result)
    @lock.synchronize { results << result }
    result.tick(@tick)
  end

  private

  def queue = @_queue ||= Queue.new.tap { |pending| @ids.each { |id| pending << id } }
end
