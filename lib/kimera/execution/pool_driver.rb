# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "child_process"
require_relative "last_words"
require_relative "shift"
require_relative "stack_dump"
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

      def pulse
        pipes.res_w.puts(JSON.generate(t: "tick"))
      end

      def finish(database, error)
        confess(error) if error
        database.before_exit(index)
        pipes.res_w.close
      end

      def confess(error)
        pipes.res_w.puts(JSON.generate(t: "crash", detail: Kimera::Execution::LastWords.new(error).to_s))
      rescue IOError, SystemCallError
        nil
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

  def budget=(budget)
    @options[:budget] = budget
  end

  def drive(queue, spawner, resolve:, lost:, trace: nil, jobs: @options.fetch(:jobs))
    database.before_fork
    Dir.mktmpdir("kimera-stacks") do |dir|
      @options[:stacks] = Kimera::Execution::StackDump.new(dir)
      Kimera::Execution::WorkerPool.new(
        queue: queue, spawner: spawner, jobs: jobs,
        hard_timeout: @options.fetch(:hard), resolve: resolve, lost: lost, trace: trace
      ).run
    end
  end

  def worker(index = nil)
    launch(:serve, index)
  end

  def channel(index = nil)
    launch(:coverage, index)
  end

  private

  def database = @options.fetch(:paralleldb)

  def stacks = @options[:stacks]

  def launch(entry, index)
    duty = Duty.new(entry, index, channels)
    [spawn(duty), *duty.pipes.parent!, stacks]
  end

  def channels
    request, response = Array.new(2) { IO.pipe }
    Channels.new(*request, *response)
  end

  def spawn(duty)
    fork do
      stacks&.arm!
      boot(duty)
    end
  end

  def boot(duty)
    duty.pipes.child!
    silence!
    database.after_fork(duty.index)
    serve(duty)
    exit!(0)
  end

  def serve(duty)
    duty.run(build(duty))
  ensure
    duty.finish(database, $ERROR_INFO)
  end

  def build(duty)
    Kimera::Execution::Shift.new(
      adapter: @adapter, registry: @registry, coverage: coverage, isolation: @isolation,
      soft_timeout: @options.fetch(:soft), leak_every: @options.fetch(:leak), pulse: pulse(duty),
      **@options.slice(:budget)
    )
  end

  def pulse(duty) = -> { duty.pulse }
end
