# frozen_string_literal: true

require "English"
require "json"
require_relative "../error"
require_relative "../results/result"
require_relative "../results/run_report"
require_relative "../runtime"
require_relative "../self_protection"
require_relative "baseline_pass"
require_relative "boot"
require_relative "child_process"
require_relative "isolation"
require_relative "null_progress"
require_relative "parallel_test_databases"
require_relative "pool_driver"
require_relative "reload"
require_relative "rig"
require_relative "schedule"
require_relative "schemata"
require_relative "verdicts"
require_relative "shift"
require_relative "worker_pool"

class Kimera::Execution::Harness
  include Kimera::Execution::ChildProcess

  Context = Data.define(:registry, :adapter, :options)
  State = Struct.new(:skipped, :irrelevant, :isolation)

  class << self
    def new(registry:, adapter:, **options)
      super(Context.new(registry, adapter, options), State.new({}, [], nil))
    end
  end

  def initialize(context, state)
    @context = context
    @state = state
  end

  def warm!(test_files)
    overlay!(test_files).tap do
      measure!
      notice
    end
  end

  def without_coverage!(test_files)
    overlay!(test_files).tap do
      verify!
    end
  end

  def overlay!(test_files)
    boot.suite(test_files)
    loader = Kimera::Execution::Schemata.new(registry, root: root, errors: errors)
    loader.overlay!.tap { complete(loader) }
  end

  def load! = boot.load!

  def isolate! = (state.isolation = boot.isolate(isolation))

  def run(ids: mutants, label: "mutants")
    schedule.run(ids, coverage: coverage, label: label)
  end

  def coverage = options[:coverage]

  def skipped = state.skipped

  private

  attr_reader :context, :state

  def registry = context.registry
  def adapter = context.adapter
  def options = context.options

  def root = options.fetch(:source_root, ".")

  def errors = options.fetch(:errio, $stderr)

  def isolation = state.isolation ||= options.fetch(:isolation) { Kimera::Execution::Isolation.new }

  def soft = options.fetch(:soft_timeout, 5.0)

  def hard = @_hard ||= options.fetch(:hard_timeout) { soft ? (soft * 3) + 1 : 30.0 }

  def jobs = @_jobs ||= [Integer(options.fetch(:jobs, 1)), 1].max

  def progress = options.fetch(:progress, Kimera::Execution::NullProgress)

  def driver = rig.driver

  def spawner = rig.spawner

  def schedule = rig.schedule

  def rig
    @_rig ||= Kimera::Execution::Rig.new(
      registry: registry, adapter: adapter, isolation: isolation, root: root,
      soft: soft, hard: hard, leak: options.fetch(:leak_every, 10), jobs: jobs,
      coverage: coverage, spawner: options[:spawner], progress: progress
    )
  end

  def boot
    @_boot ||= Kimera::Execution::Boot.new(adapter: adapter, isolate: options[:isolate_db], errors: errors)
  end

  def complete(loader)
    state.skipped = loader.skipped
    isolate!
  end

  def mutants = registry.each.map { |mutant, _path| mutant.id }

  def measure!
    pass = baseline
    measured = jobs > 1 ? parallel(pass) : pass.measure!
    options[:coverage] = measured.coverage
    driver.coverage = coverage
    state.irrelevant = measured.irrelevant
  end

  def parallel(pass)
    pass.parallel! do |resolve:, lost:|
      driver.drive(adapter.test_ids, driver.method(:channel), resolve: resolve, lost: lost)
    end
  end

  def verify! = baseline.check!

  def baseline
    Kimera::Execution::BaselinePass.new(adapter: adapter, registry: registry, progress: progress)
  end

  def notice
    count = state.irrelevant.size
    return if count.zero?
    errors.puts(message(count))
  end

  def message(count)
    "kimera: #{count} failing test(s) cover no in-scope mutant and were " \
      "excluded from the baseline (they gate nothing this run)"
  end
end
