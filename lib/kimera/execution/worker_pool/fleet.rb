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

  def fetch(pipe) = workers.fetch(pipe)

  def keys = workers.keys

  def any? = workers.any?

  def take(worker)
    (worker.fresh? && rechecks.shift) || following
  end

  def requeue(id)
    rechecked.add(id)
    rechecks.push(id)
  end

  def recheck?(id)
    rechecked.include?(id)
  end

  def done!(id)
    done[id] = true
  end

  def progress!
    guard.progress!
  end

  def remove(pipe, reason: :crash, stacks: nil)
    worker = workers.delete(pipe)
    slots.push(worker.slot)
    close(worker)
    charge(worker, reason, bury(worker.pid), stacks)
    refill
  end

  def disband
    workers.each_value do |worker|
      close(worker)
      stop(worker.pid)
    end
  end

  private

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

  def workers = @_workers ||= {}

  def slots = @_slots ||= (0...@jobs).to_a

  def guard = @_guard ||= Kimera::Execution::WorkerPool::StillbornGuard.new(@jobs)

  def spawn
    slot = slots.shift
    pid, request, pipe, stacks = @spawner.call(slot)
    workers[pipe] = Kimera::Execution::WorkerPool::Worker.new(pid, request, pipe, nil, nil, slot, stacks)
  end

  def close(worker)
    shut(worker.response)
    shut(worker.request)
  end

  def charge(worker, reason, status, stacks)
    id = worker.inflight
    return unless id
    done!(id)
    @pool.lost(id, reason, reason == :crash ? crashed(worker, status) : stacks)
  end

  def crashed(worker, status)
    guard.track(status)
    worker.obituary(status)
  end

  def refill
    missing = @jobs - workers.size
    missing.times do
      break unless pending?
      replace
    end
  end

  def pending?
    rechecks.any? || queue.any? { |id| !done[id] }
  end

  def replace
    spawn
    @pool.assign(workers.values.last)
  end
end
