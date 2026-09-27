# frozen_string_literal: true

require "json"
require_relative "../error"
require_relative "child_process"

class Kimera::Execution::WorkerPool
  include Kimera::Execution::ChildProcess

  Context = Data.define(:queue, :spawner, :resolve, :lost, :options)

  POLL_INTERVAL = 0.2

  class << self
    def new(queue:, spawner:, resolve:, lost:, **options)
      super(Context.new(queue, spawner, resolve, lost, options))
    end
  end

  def initialize(context)
    @context = context
  end

  def run
    bootstrap
    poll while fleet.any?
  end

  def assign(worker)
    id = fleet.take(worker)
    return close(worker) unless id
    worker.claim(id, limit)
    trace(worker.slot, id)
    worker.offer(id, recheck: fleet.recheck?(id))
  end

  def lost(id, reason, stacks = nil) = context.lost.call(id, reason, stacks)

  private

  attr_reader :context

  def limit = context.options.fetch(:hard_timeout)

  def fleet
    @_fleet ||= Kimera::Execution::WorkerPool::Fleet.new(
      queue: context.queue, spawner: context.spawner, jobs: context.options.fetch(:jobs), pool: self
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
    line = pipe.gets
    return fleet.remove(pipe) unless line
    message = parse(line)
    dispatch(worker, message) if message
  end

  def dispatch(worker, message)
    case message["t"]
    when "result" then finish(worker, message)
    when "ready" then assign(worker)
    when "leak", "requeue" then close(worker) if relay(message)
    end
  end

  def relay(message)
    context.resolve.call(message)
    requeue = message["t"] == "requeue"
    fleet.requeue(message["id"]) if requeue
    requeue
  end

  def finish(worker, message)
    fleet.done!(message["id"])
    fleet.progress!
    context.resolve.call(message)
    worker.idle!
    worker.renew(limit)
  end

  def trace(slot, id) = context.options[:trace]&.call(slot, id)

  def close(worker) = shut(worker.retire)

  def watch
    current = now
    fleet.pairs { |pipe, worker| expire(pipe, worker.halt) if worker.expired?(current) }
  end

  def expire(pipe, stacks) = fleet.remove(pipe, reason: :timeout, stacks: stacks)
end

require_relative "worker_pool/fleet"
require_relative "worker_pool/worker"
