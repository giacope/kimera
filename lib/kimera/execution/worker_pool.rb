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
    bootstrap
    poll while fleet.any?
  ensure
    fleet.disband
  end

  def assign(worker)
    id = fleet.take(worker)
    return close(worker) unless id
    worker.claim(id, limit)
    trace(worker.slot, id)
    worker.offer(id, recheck: fleet.recheck?(id))
  end

  def lost(id, reason, stacks = []) = listeners.lost.call(id, reason, stacks)

  private

  attr_reader :listeners

  def limit = @options.fetch(:hard_timeout)

  def fleet = @_fleet ||= @options.fetch(:fleet) { manned }

  def manned
    Kimera::Execution::WorkerPool::Fleet.new(
      queue: @queue, spawner: @spawner, jobs: @options.fetch(:jobs), pool: self
    )
  end

  def bootstrap
    fleet.bootstrap
    fleet.each { |worker| assign(worker) }
  end

  def poll
    ready, = IO.select(fleet.keys, nil, nil, POLL_INTERVAL)
    Array(ready).each { |pipe| service(pipe) }
    watch
  end

  def service(pipe)
    worker = fleet.fetch(pipe)
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

  def relay(message) = listeners.resolve.call(message)

  def requeue(worker, message)
    relay(message)
    fleet.requeue(message["id"])
    close(worker)
  end

  def finish(worker, message)
    fleet.done!(message["id"])
    fleet.progress!
    relay(message)
    worker.idle!
  end

  def trace(slot, id) = listeners.trace&.call(slot, id)

  def close(worker) = shut(worker.retire(limit))

  def watch
    current = now
    fleet.pairs { |pipe, worker| expire(pipe, worker.halt) if worker.expired?(current) }
  end

  def expire(pipe, stacks) = fleet.remove(pipe, reason: :timeout, stacks: stacks)
end

require_relative "worker_pool/fleet"
require_relative "worker_pool/worker"
require_relative "worker_pool/listeners"
