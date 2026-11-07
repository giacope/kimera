# frozen_string_literal: true

require "json"
require_relative "../error"
require_relative "child_process"

class Kimera::Execution::WorkerPool
  include Kimera::Execution::ChildProcess

  POLL_INTERVAL = 0.2
  CHUNK = 65_536

  def initialize(queue, spawner, listeners, options)
    @queue = queue
    @spawner = spawner
    @listeners = listeners
    @options = options
  end

  def run
    fleet.bootstrap(@queue.size)
    poll while fleet.any?
  ensure
    fleet.disband
  end

  def assign(worker)
    id, recheck = backlog.take(worker)
    return close(worker) unless id
    worker.claim(id, limit)
    worker.trace(listeners, id)
    worker.offer(id, recheck: recheck)
  end

  def lost(id, reason, stacks = []) = listeners.lost(id, reason, stacks)

  private

  attr_reader :listeners

  def limit = @options.fetch(:hard_timeout)

  def backlog = @_backlog ||= @options.fetch(:backlog) { Kimera::Execution::WorkerPool::Backlog.new(@queue) }

  def fleet = @_fleet ||= @options.fetch(:fleet) { manned }

  def manned
    Kimera::Execution::WorkerPool::Fleet.new(
      backlog: backlog, spawner: @spawner, jobs: @options.fetch(:jobs), pool: self
    )
  end

  def poll
    ready, = IO.select(fleet.map(&:first), nil, nil, POLL_INTERVAL)
    Array(ready).each { |pipe| service(pipe) }
    watch
  end

  def service(pipe)
    worker = fleet[pipe]
    chunk = pipe.read_nonblock(CHUNK, exception: false)
    return hangup(pipe, worker) unless chunk
    worker.feed(chunk) { |line| deliver(worker, line) } unless chunk == :wait_readable
  end

  def hangup(pipe, worker)
    deliver(worker, worker.rest)
    fleet.remove(pipe)
  end

  def deliver(worker, line)
    message = parse(line) { return }
    dispatch(worker.heard(message, limit), message)
  end

  def dispatch(worker, message)
    case message["t"]
    when "result" then finish(worker, message)
    when "ready" then assign(worker)
    when "leak" then relay(message)
    when "requeue" then requeue(worker, message)
    end
  end

  def relay(message) = listeners.resolved(message)

  def requeue(worker, message)
    relay(message)
    backlog.requeue(message["id"])
    close(worker)
  end

  def finish(worker, message)
    backlog.done!(message["id"])
    fleet.progress!
    relay(message)
    worker.idle!
  end

  def close(worker) = shut(worker.retire(limit))

  def watch
    current = now
    fleet.to_a.each { |pipe, worker| expire(pipe, worker.halt) if worker.expired?(current) }
  end

  def expire(pipe, stacks) = fleet.remove(pipe, reason: :timeout, stacks: stacks)
end

require_relative "worker_pool/backlog"
require_relative "worker_pool/fleet"
require_relative "worker_pool/worker"
require_relative "worker_pool/listeners"
