# frozen_string_literal: true

class Kimera::Execution::WorkerPool::Backlog
  def initialize(source)
    @source = source
  end

  def take(worker)
    id = chosen(worker)
    id ? [id, rechecked.include?(id)] : []
  end

  def requeue(id)
    rechecked.add(id)
    rechecks.push(id)
  end

  def done!(id)
    done[id] = true
  end

  def pending?
    rechecks.any? || queue.any? { |id| !done[id] }
  end

  private

  def chosen(worker) = (worker.fresh? && rechecks.shift) || following

  def following
    until queue.empty?
      id = queue.shift
      return id unless done[id]
    end
  end

  def queue = @_queue ||= @source.dup

  def done = @_done ||= {}

  def rechecks = @_rechecks ||= []

  def rechecked = @_rechecked ||= Set.new
end
