# frozen_string_literal: true

require_relative "child_process"
require_relative "shift"
require_relative "worker_pool"

class Kimera::Execution::Pool
  include Kimera::Execution::ChildProcess

  Channels =
    Struct.new(:req_r, :req_w, :res_r, :res_w) do
      def parent!
        req_r.close
        res_w.close
        [req_w, res_r]
      end

      def child!
        req_w.close
        res_r.close
      end
    end

  Duty =
    Struct.new(:entry, :index, :pipes) do
      def run(shift)
        shift.public_send(entry, pipes.req_r, pipes.res_w)
      end

      def finish(database)
        database.before_exit(index)
        pipes.res_w.close
      end
    end

  def initialize(adapter:, registry:, isolation:, **options)
    @adapter = adapter
    @registry = registry
    @isolation = isolation
    @options = options
  end

  def coverage = @options[:coverage]

  def coverage=(measured)
    @options[:coverage] = measured
  end

  def drive(queue, spawner, resolve:, lost:)
    Kimera::Execution::WorkerPool.new(
      queue: queue, spawner: spawner, jobs: @options.fetch(:jobs),
      hard_timeout: @options.fetch(:hard), resolve: resolve, lost: lost
    ).run
  end

  def worker(index = nil)
    launch(:serve, index)
  end

  def channel(index = nil)
    launch(:coverage, index)
  end

  private

  def database = @options.fetch(:paralleldb)

  def launch(entry, index)
    database.before_fork
    duty = Duty.new(entry, index, channels)
    [spawn(duty), *duty.pipes.parent!]
  end

  def channels
    request, response = Array.new(2) { IO.pipe }
    Channels.new(*request, *response)
  end

  def spawn(duty) = fork { boot(duty) }

  def boot(duty)
    duty.pipes.child!
    silence!
    database.after_fork(duty.index)
    serve(duty)
    exit!(0)
  end

  def serve(duty)
    duty.run(build)
  ensure
    duty.finish(database)
  end

  def build
    Kimera::Execution::Shift.new(
      adapter: @adapter, registry: @registry, coverage: coverage,
      isolation: @isolation, soft_timeout: @options.fetch(:soft), leak_every: @options.fetch(:leak)
    )
  end
end
