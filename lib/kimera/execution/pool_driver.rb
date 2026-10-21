# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "child_process"
require_relative "patience"
require_relative "pool_duty"
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

  Armed = Struct.new(:coverage, :budget, :timings, :stacks)

  def initialize(adapter:, registry:, isolation:, **options)
    @adapter = adapter
    @registry = registry
    @isolation = isolation
    @options = options
  end

  def coverage = armed.coverage

  def arm(coverage:, budget:, timings:)
    armed.coverage = coverage
    armed.budget = budget
    armed.timings = timings
  end

  def narrow(coverage) = armed.coverage = coverage

  def drive(queue, spawner, listeners, jobs: @options.fetch(:jobs))
    database.before_fork
    Dir.mktmpdir("kimera-stacks") do |dir|
      armed.stacks = Kimera::Execution::StackDump.new(dir)
      Kimera::Execution::WorkerPool.new(
        Kimera::Execution::WorkerPool::Context.new(
          queue, spawner, listeners, { jobs: jobs, hard_timeout: @options.fetch(:hard) }
        )
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

  def stacks = armed.stacks

  def armed = @_armed ||= Armed.new(*@options.values_at(:coverage, :budget, :timings))

  def launch(entry, index)
    duty = Duty.new(entry, index, channels)
    [spawn(duty), *duty.pipes.parent!, stacks]
  end

  def channels
    request, response = Array.new(2) { IO.pipe(Encoding::UTF_8) }
    Channels.new(*request, *response)
  end

  def spawn(duty)
    fork do
      lead
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
    duty.retire(database, $ERROR_INFO)
  end

  def build(duty)
    Kimera::Execution::Shift.new(
      adapter: @adapter, registry: @registry, coverage: coverage, isolation: @isolation,
      soft_timeout: @options.fetch(:soft), pulse: pulse(duty), ceiling: soft_ceiling,
      **@options.slice(:quality, :confirm), **{ budget: armed.budget, timings: armed.timings }.compact
    )
  end

  def pulse(duty) = -> { duty.pulse }

  def soft_ceiling
    hard = @options[:hard]
    hard && (hard - Kimera::Execution::Patience::SLACK)
  end
end
