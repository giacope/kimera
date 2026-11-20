# frozen_string_literal: true

class Kimera::Execution::WorkerPool::Backlog
  def initialize(source)
    @source = source
  end

  def take
    until queue.empty?
      id = queue.shift
      return id unless done[id]
    end
  end

  def done!(id)
    done[id] = true
  end

  def pending? = queue.any? { |id| !done[id] }

  private

  def queue = @_queue ||= @source.dup

  def done = @_done ||= {}
end
