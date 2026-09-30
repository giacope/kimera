# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Sweep
  def initialize(ids, lock)
    @ids = ids
    @lock = lock
  end

  def results = @_results ||= []

  def pop = queue.pop(timeout: 0)

  def each(&) = @ids.each(&)

  def record(result)
    @lock.synchronize { results << result }
  end

  private

  def queue = @_queue ||= Queue.new.tap { |pending| @ids.each { |id| pending << id } }
end
