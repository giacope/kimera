# frozen_string_literal: true

require "English"
require "json"
require_relative "../error"
require_relative "../results/result"
require_relative "../results/run_report"
require_relative "../runtime"
require_relative "../self_protection"
require_relative "baseline_screen"
require_relative "baseline_pass"
require_relative "baseline_stall"
require_relative "boot"
require_relative "flake_runs"
require_relative "child_process"
require_relative "isolated"
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
require_relative "survey"
require_relative "time_budget"
require_relative "unmeasured"
require_relative "worker_pool"

class Kimera::Execution::Harness
  include Kimera::Execution::ChildProcess

  class << self
    def build(registry:, adapter:, **options) = new(registry, adapter, options)
  end

  def initialize(registry, adapter, options)
    @registry = registry
    @adapter = adapter
    @options = options
  end

  def warm!(test_files, scope: nil)
    overlay!(test_files).tap do
      measured = measure!
      excluded = measured.screened(screen)
      sift!(scope)
      notice(excluded, measured)
    end
  end

  def without_coverage!(test_files) = overlay!(test_files).tap { verify! }

  def run(ids: mutants, label: "mutants") = schedule.run(ids, coverage: coverage, label: label)

  def survey = Kimera::Execution::Survey.new(options, adapter)

  private

  attr_reader :registry, :adapter, :options

  def coverage = survey.coverage

  def overlay!(test_files)
    trace.record { boot.suite(test_files) }
    loader = Kimera::Execution::Schemata.new(registry, root: root, errors: errors, loaded: trace.method(:loaded?))
    loader.overlay!.tap { complete(loader) }
  end

  def load! = boot.load!

  def isolate! = (options[:isolation] = boot.isolate(isolation))

  def root = options.fetch(:source_root, ".")

  def errors(standard = $stderr) = options.fetch(:errio, standard)

  def isolation = options[:isolation] ||= Kimera::Execution::Isolation.new

  def soft = options.fetch(:soft_timeout, 5.0)

  def hard = @_hard ||= options.fetch(:hard_timeout) { soft ? (soft * 3) + 1 : 30.0 }

  def jobs = @_jobs ||= [Integer(options.fetch(:jobs, 1)), 1].max

  def progress = options.fetch(:progress) { Kimera::Execution::NullProgress.new }

  def driver = rig.driver

  def schedule = rig.schedule

  def rig = @_rig ||= options.fetch(:rig) { rigged }

  def rigged
    Kimera::Execution::Rig.new(
      registry: registry, adapter: adapter, isolation: isolation, root: root, soft: soft, hard: hard, jobs: jobs,
      coverage: coverage, spawner: options[:spawner], progress: progress, aliases: options[:aliases],
      **options.slice(:filter, :test_quality, :confirm_survivors, :zygote)
    )
  end

  def trace = @_trace ||= options.fetch(:trace) { Kimera::Execution::LoadTrace.new(registry, root) }

  def boot = @_boot ||= options.fetch(:boot) { booted }

  def booted = Kimera::Execution::Boot.new(adapter: adapter, isolate: options[:isolate_db], errors: errors)

  def complete(loader)
    options[:aliases] = loader.aliases
    isolate!
  end

  def mutants = registry.each.map { |mutant, _path| mutant.id }

  def measure!
    parallel(baseline).tap do |measured|
      options.update(measured.to_h.slice(:coverage, :timings))
      arm(options.fetch(:timings))
    end
  end

  def sift!(scope)
    trace.quarantine!(coverage)
    Kimera::Execution::OrderTrace.new(registry).follow!(baseline, coverage, scope: scope, progress: progress)
    options[:flakes] = rig.hunt(coverage, scope, reruns)
  end

  def reruns = Kimera::Execution::FlakeRuns.new(*options.values_at(:seed, :flaky_runs, :filter))

  def arm(timings) = driver.arm(coverage: coverage, budget: budget(timings), timings: timings)

  def parallel(pass)
    pass.parallel!(jobs) do |ids, width, listeners|
      driver.drive(ids, driver.spawner(:coverage), listeners, jobs: width || jobs)
    end
  end

  def verify!
    progress.note("baseline (whole suite, no coverage)")
    baseline.check!
  end

  def budget(timings)
    return Kimera::Execution::TimeBudget.new({}) if options[:relative_timeout] == false
    Kimera::Execution::TimeBudget.new(timings, **tuning)
  end

  def tuning = { factor: options[:timeout_factor], slack: options[:timeout_slack] }.compact

  def baseline
    Kimera::Execution::BaselinePass.new(adapter:, registry:, root:, **options.slice(:progress, :measured, :zygote))
  end

  def screen = Kimera::Execution::BaselineScreen.new(adapter: adapter, root: root, jobs: jobs)

  def notice(excluded, measured)
    stall = measured.stall(hard: hard, jobs: jobs)
    errors.puts(stall) if stall
    errors.puts(excluded) if excluded
  end
end
