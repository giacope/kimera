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
    id = fleet.take
    return close(worker) unless id
    worker.busy!(id)
    worker.renew(limit)
    worker.offer(id)
  end

  def lost(id, reason) = context.lost.call(id, reason)

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
    when "leak" then context.resolve.call(message)
    when "ready" then assign(worker)
    end
  end

  def finish(worker, message)
    fleet.done!(message["id"])
    fleet.progress!
    context.resolve.call(message)
    worker.idle!
    worker.renew(limit)
  end

  def close(worker) = shut(worker.retire)

  def watch
    current = now
    fleet.pairs { |pipe, worker| expire(pipe, worker, current) }
  end

  def expire(pipe, worker, current)
    return unless worker.expired?(current)
    kill(worker.pid)
    fleet.remove(pipe, reason: :timeout)
  end
end

require_relative "worker_pool/fleet"
require_relative "worker_pool/worker"
