# frozen_string_literal: true

require_relative "stillborn_guard"

class Kimera::Execution::WorkerPool::Fleet
  include Kimera::Execution::ChildProcess

  def initialize(queue:, spawner:, jobs:, pool:)
    @source = queue
    @spawner = spawner
    @jobs = jobs
    @pool = pool
  end

  def bootstrap
    [@jobs, queue.size].min.times { spawn }
  end

  def each(&)
    workers.each_value(&)
  end

  def pairs(&)
    workers.to_a.each(&)
  end

  def fetch(pipe)
    workers.fetch(pipe)
  end

  def keys
    workers.keys
  end

  def any?
    workers.any?
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

  def progress!
    guard.progress!
  end

  def remove(pipe, reason: :crash)
    worker = workers.delete(pipe)
    slots.push(worker.slot)
    close(worker)
    charge(worker.inflight, reason, reap(worker.pid))
    refill
  end

  private

  def queue = @_queue ||= @source.dup

  def done = @_done ||= {}

  def workers = @_workers ||= {}

  def slots = @_slots ||= (0...@jobs).to_a

  def guard = @_guard ||= Kimera::Execution::WorkerPool::StillbornGuard.new(@jobs)

  def spawn
    slot = slots.shift
    pid, request, pipe = @spawner.call(slot)
    workers[pipe] = Kimera::Execution::WorkerPool::Worker.new(pid, request, pipe, nil, nil, slot)
  end

  def close(worker)
    shut(worker.response)
    shut(worker.request)
  end

  def charge(id, reason, status)
    return unless id
    guard.track(status) if reason == :crash
    done!(id)
    @pool.lost(id, reason)
  end

  def refill
    missing = @jobs - workers.size
    missing.times do
      break unless queue.any? { |id| !done[id] }
      replace
    end
  end

  def replace
    spawn
    @pool.assign(workers.values.last)
  end
end
