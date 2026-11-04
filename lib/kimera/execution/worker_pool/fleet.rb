# frozen_string_literal: true

require_relative "stillborn_guard"

class Kimera::Execution::WorkerPool::Fleet
  include Kimera::Execution::ChildProcess
  include Enumerable

  def initialize(backlog:, spawner:, jobs:, pool:)
    @backlog = backlog
    @spawner = spawner
    @jobs = jobs
    @pool = pool
  end

  def bootstrap(size)
    [@jobs, size].min.times { spawn }
    workers.each_value { |worker| @pool.assign(worker) }
  end

  def each(&)
    workers.each(&)
  end

  def [](pipe) = workers.fetch(pipe)

  def progress!
    guard.progress!
  end

  def remove(pipe, reason: :crash, stacks: [])
    slots.push(seats.delete(pipe))
    retire(workers.delete(pipe), reason, stacks)
    refill
  end

  def disband
    workers.each_value(&:dismiss)
  end

  private

  def workers = @_workers ||= {}

  def seats = @_seats ||= {}

  def slots = @_slots ||= (0...@jobs).to_a

  def guard(guards = Kimera::Execution::WorkerPool::StillbornGuard) = @_guard ||= guards.new(@jobs)

  def spawn
    slot = slots.shift
    pid, request, pipe, stacks = @spawner.call(slot)
    seats[pipe] = slot
    workers[pipe] = Kimera::Execution::WorkerPool::Worker.new(pid, request, pipe, nil, nil, slot, stacks)
  end

  def retire(worker, reason, stacks)
    worker.disconnect
    charge(worker, reason, worker.buried, stacks)
  end

  def charge(worker, reason, status, stacks)
    worker.forfeit do |id|
      @backlog.done!(id)
      @pool.lost(id, reason, reason == :crash ? crashed(worker, status) : stacks)
    end
  end

  def crashed(worker, status)
    worker.inform(guard, status)
    worker.obituary(status)
  end

  def refill
    missing = @jobs - workers.size
    missing.times do
      break unless @backlog.pending?
      replace
    end
  end

  def replace
    spawn
    @pool.assign(workers.values.last)
  end
end
