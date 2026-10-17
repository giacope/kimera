# frozen_string_literal: true

require "English"
require "json"
require_relative "../error"
require_relative "../results/result"
require_relative "../results/run_report"
require_relative "../runtime"
require_relative "../self_protection"
require_relative "baseline_exclusions"
require_relative "baseline_pass"
require_relative "baseline_stall"
require_relative "boot"
require_relative "child_process"
require_relative "flake_hunt"
require_relative "isolation"
require_relative "load_trace"
require_relative "order_trace"
require_relative "null_progress"
require_relative "worker_databases"
require_relative "pool_driver"
require_relative "reload"
require_relative "rig"
require_relative "schedule"
require_relative "schemata"
require_relative "verdicts"
require_relative "shift"
require_relative "time_budget"
require_relative "worker_pool"

class Kimera::Execution::Harness
  include Kimera::Execution::ChildProcess

  Context = Data.define(:registry, :adapter, :options)
  State = Struct.new(:skipped, :irrelevant, :isolation, :recovered, :aliases)

  class << self
    def build(registry:, adapter:, **options) = new(Context.new(registry, adapter, options), State.new({}, {}, nil, {}))
  end

  def initialize(context, state)
    @context = context
    @state = state
  end

  def warm!(test_files, scope: nil)
    overlay!(test_files).tap do
      measure!
      sift!(scope)
      notice
    end
  end

  def without_coverage!(test_files) = overlay!(test_files).tap { verify! }

  def overlay!(test_files)
    trace.record { boot.suite(test_files) }
    loader = Kimera::Execution::Schemata.new(registry, root: root, errors: errors)
    loader.overlay!.tap { complete(loader) }
  end

  def load! = boot.load!

  def isolate! = (state.isolation = boot.isolate(isolation))

  def run(ids: mutants, label: "mutants")
    schedule.run(ids, coverage: coverage, label: label)
  end

  def coverage = options[:coverage]

  def timings = options.fetch(:timings, {})

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
      registry: registry, adapter: adapter, isolation: isolation, root: root, soft: soft, hard: hard, jobs: jobs,
      coverage: coverage, spawner: options[:spawner], progress: progress, aliases: state.aliases,
      **options.slice(:filter, :test_quality)
    )
  end

  def trace = @_trace ||= Kimera::Execution::LoadTrace.new(registry, root)

  def boot = @_boot ||= Kimera::Execution::Boot.new(adapter: adapter, isolate: options[:isolate_db], errors: errors)

  def complete(loader)
    state.skipped = loader.skipped
    state.aliases = loader.aliases
    isolate!
  end

  def mutants = registry.each.map { |mutant, _path| mutant.id }

  def measure!
    measured = parallel(baseline)
    options[:coverage] = measured.coverage
    options[:timings] = measured.timings
    arm(measured.timings)
    state.irrelevant = measured.irrelevant
    state.recovered = measured.recovered
  end

  def sift!(scope)
    trace.quarantine!(coverage)
    Kimera::Execution::OrderTrace.new(registry).follow!(baseline, coverage, scope: scope, progress: progress)
    Kimera::Execution::FlakeHunt.new(adapter, driver, progress).call(coverage, scope, options)
  end

  def arm(timings)
    driver.coverage = coverage
    driver.budget = budget(timings)
    driver.timings = timings
  end

  def parallel(pass)
    pass.parallel!(jobs) do |ids, width, listeners|
      driver.drive(ids, driver.method(:channel), listeners, jobs: width || jobs)
    end
  end

  def verify!
    progress.note("baseline (whole suite, no coverage)")
    baseline.check!
  end

  def budget(timings)
    return Kimera::Execution::TimeBudget::NONE if options[:relative_timeout] == false
    Kimera::Execution::TimeBudget.new(timings, **tuning)
  end

  def tuning = { factor: options[:timeout_factor], slack: options[:timeout_slack] }.compact

  def baseline = Kimera::Execution::BaselinePass.new(adapter: adapter, registry: registry, progress: progress)

  def notice
    stall = Kimera::Execution::BaselineStall.new(state.recovered, hard: hard, jobs: jobs).to_s
    errors.puts(stall) if stall
    excluded = Kimera::Execution::BaselineExclusions.new(state.irrelevant).to_s
    errors.puts(excluded) if excluded
  end
end
