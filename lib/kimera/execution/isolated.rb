# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../results/result"
require_relative "../results/run_report"
require_relative "../synthesis/overlay"
require_relative "baseline_failure"
require_relative "block_use"
require_relative "isolated_plan"
require_relative "isolated_scheduling"
require_relative "isolated_verdict"
require_relative "isolated_watchdog"
require_relative "macro_lambdas"
require_relative "mirror_layout"
require_relative "mirror_slots"
require_relative "null_progress"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedExecution
  include Kimera::Execution::IsolatedScheduling
  include Kimera::Execution::IsolatedVerdict

  DEFAULT_HARD_TIMEOUT = 300.0
  def initialize(registry:, root:, tests:, **options)
    @registry = registry
    @root = root
    @tests = tests
    @options = options
  end

  def verify!(ids)
    tests = plan.needed(ids)
    return if tests.empty?
    progress.note("isolated baseline (unmutated mirror)")
    outcome = with_mirror { |mirror| verdict(Kimera::Execution::Bay.new(mirror), tests) }
    outcome.confirmed(ids) do
      failure = Kimera::Execution::BaselineFailure::Mirror.new(outcome.to_s, layout)
      raise(Kimera::Execution::BaselineFailure, failure.to_s)
    end
  end

  def run(ids: self.ids, label: "mutants")
    progress.during(ids.size, label) { |tick| report(ids, tick) }
  end

  def rejudge(warm, label:)
    count = warm.size
    progress.note("re-judging #{count} mutant(s) the warm pass could not judge, each in a fresh mirror")
    progress.during(count, label) do |tick|
      verdicts = alone(warm.map(&:mutant_id), tick)
      warm.map { |result| noted(verdicts.fetch(result.mutant_id), result) }
    end
  end

  private

  attr_reader :registry

  def with_mirror(&)
    ready!
    super
  end

  def ready!
    released = slots.tap(&:release!)
    return if @_ready || jobs == 1
    @_ready = true
    released.prepare
  end

  def slots = @options.fetch(:slots) { Kimera::Execution::MirrorSlots.new(jobs) }

  def progress = @options.fetch(:progress) { Kimera::Execution::NullProgress.new }

  def limit = @options.fetch(:hard_timeout, DEFAULT_HARD_TIMEOUT)

  def watchdog = Kimera::Execution::IsolatedWatchdog.new(limit, poll: @options.fetch(:poll_interval, 0.05))

  def dirs = @options.fetch(:dirs, Dir)

  def rulings = @options.fetch(:rulings, Kimera::Execution::IsolatedOutcome::Ruling)

  def layout = @_layout ||= @options.fetch(:layout) { Kimera::Execution::MirrorLayout.new(@root, @registry) }

  def quality? = @options[:test_quality] == true

  def timings = @options.fetch(:timings, {})

  def jobs = @_jobs ||= [Integer(@options.fetch(:jobs, 1)), 1].max

  def plan = @_plan ||= @options.fetch(:plan) { planned }

  def planned
    Kimera::Execution::IsolatedPlan.new(
      registry: @registry, layout: layout, tests: @tests,
      coverage: @options.fetch(:coverage, {}), framework: @options.fetch(:framework, "rspec"),
      test_files: @options.fetch(:test_files, []), filter: @options[:filter], seed: @options[:seed],
      test_paths: @options[:test_paths], warnings: @options.fetch(:warnings, [])
    )
  end

  def noted(result, warm)
    judged = covered?(warm) ? covered(result, warm) : result
    judged.tap { judged.note = "judged in a fresh isolated mirror; the warm pass could not: #{warm.detail}" }
  end

  def covered?(warm) = @registry.index.fetch(warm.mutant_id).reasons(Kimera::Reason.warm).any?

  def covered(result, warm)
    kept = result.killed? || warm.status == :survived ? result : warm.dup
    kept.tap { kept.covering_tests = [*warm.covering_tests, *result.failing_tests].uniq }
  end

  def report(ids, tick)
    Kimera::RunReport.new(
      results: (jobs > 1 ? concurrently(ids, tick) : serially(ids, tick)),
      leaks: [], registry: @registry
    )
  end
end
