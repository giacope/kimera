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
      private(*members)
      def parent!
        req_r.close
        res_w.close
        [req_w, res_r]
      end

      def child!
        req_w.close
        res_r.close
      end

      def serve(shift, entry) = shift.public_send(entry, req_r, res_w)

      def say(line) = res_w.puts(line)

      def close = res_w.close
    end

  Armed =
    Struct.new(:coverage, :budget, :timings, :stacks) do
      private(*members)
      def arm(coverage:, budget:, timings:)
        self.coverage = coverage
        self.budget = budget
        self.timings = timings
      end

      def narrow(kept) = self.coverage = kept

      def dump(found) = self.stacks = found

      def ready = stacks&.arm!

      def equip(*spawned) = [*spawned, stacks]

      def shift(**)
        Kimera::Execution::Shift.new(**, **{ coverage: coverage, budget: budget, timings: timings }.compact)
      end
    end

  class Unprepared < StandardError
    def headline = message
  end

  def initialize(adapter:, registry:, isolation:, **options)
    @adapter = adapter
    @registry = registry
    @isolation = isolation
    @options = options
  end

  def arm(coverage:, budget:, timings:) = armed.arm(coverage: coverage, budget: budget, timings: timings)

  def narrow(coverage) = armed.narrow(coverage)

  def drive(queue, spawner, listeners, jobs: @options.fetch(:jobs))
    database.before_fork
    @options.fetch(:dirs, Dir).mktmpdir("kimera-stacks") do |dir|
      armed.dump(Kimera::Execution::StackDump.new(dir))
      @options.fetch(:pools, Kimera::Execution::WorkerPool)
        .new(queue, spawner, listeners, { jobs: jobs, hard_timeout: @options.fetch(:hard) }).run
    end
  end

  def spawner(entry) = ->(index) { launch(entry, index) }

  private

  def database = @options.fetch(:paralleldb)

  def armed = @_armed ||= @options.fetch(:armed) { Armed.new(*@options.values_at(:coverage, :budget, :timings)) }

  def launch(entry, index)
    duty = Duty.new(entry, index, channels)
    armed.equip(spawn(duty), *duty.parent!)
  end

  def channels
    request, response = Array.new(2) { IO.pipe(Encoding::UTF_8) }
    Channels.new(*request, *response)
  end

  def spawn(duty)
    fork do
      lead
      armed.ready
      boot(duty)
    end
  end

  def boot(duty)
    duty.child!
    silence!
    serve(duty)
    exit!(0)
  end

  def serve(duty)
    duty.prepare(database)
    duty.run(build(duty))
  ensure
    duty.retire(database, $ERROR_INFO)
  end

  def build(duty)
    armed.shift(
      adapter: @adapter, registry: @registry, isolation: @isolation,
      soft_timeout: @options.fetch(:soft), pulse: pulse(duty), hard: hard,
      **@options.slice(:quality, :confirm, :zygote)
    )
  end

  def pulse(duty) = -> { duty.pulse }

  def hard = @options[:hard] || Float::INFINITY
end
