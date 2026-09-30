# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../results/result"
require_relative "../results/run_report"
require_relative "../synthesis/overlay"
require_relative "baseline_failure"
require_relative "isolated_plan"
require_relative "isolated_scheduling"
require_relative "isolated_verdict"
require_relative "isolated_watchdog"
require_relative "null_progress"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedExecution
  include Kimera::Execution::IsolatedExecutionScheduling
  include Kimera::Execution::IsolatedExecutionVerdict
  include Kimera::Execution::IsolatedExecutionWatchdog

  DEFAULT_HARD_TIMEOUT = 300.0

  def initialize(registry:, root:, tests:, **options)
    @registry = registry
    @root = root
    @tests = tests
    @options = options
  end

  def verify!
    errors.puts("kimera: isolated baseline (unmutated mirror)") unless progress.enabled?
    outcome = with_mirror { |mirror| verdict(mirror, plan.suite) }
    return if outcome.status == :survived
    raise(Kimera::Execution::BaselineFailure.mirrored(outcome.explain(limit), Kimera::Execution::IsolatedPlan::MIRROR_HINT))
  end

  def run(ids: self.ids, label: "mutants")
    progress.start(ids.size, label)
    report(ids)
  ensure
    progress.finish
  end

  def rejudge(warm, label:)
    announce(warm.size, label)
    verdicts = alone(warm.map(&:mutant_id))
    warm.map { |result| noted(verdicts.fetch(result.mutant_id), result) }
  ensure
    progress.finish
  end

  private

  def progress = @options.fetch(:progress, Kimera::Execution::NullProgress)

  def limit = @options.fetch(:hard_timeout, DEFAULT_HARD_TIMEOUT)

  def jobs = @_jobs ||= [Integer(@options.fetch(:jobs, 1)), 1].max

  def errors = @options.fetch(:errio, $stderr)

  def plan
    @_plan ||= Kimera::Execution::IsolatedPlan.new(
      registry: @registry, root: @root, tests: @tests,
      coverage: @options.fetch(:coverage, {}), framework: @options.fetch(:framework, "rspec"),
      test_files: @options.fetch(:test_files, [])
    )
  end

  def announce(count, label)
    progress.start(count, label)
    return if progress.enabled?
    errors.puts("kimera: re-judging #{count} mutant(s) the warm pass could not judge, each in a fresh mirror")
  end

  def noted(result, warm)
    result.tap { result.note = "judged in a fresh isolated mirror; the warm pass could not: #{warm.detail}" }
  end

  def report(ids)
    Kimera::RunReport.new(
      results: (jobs > 1 ? concurrently(ids) : serially(ids)),
      leaks: [], registry: plan.registry
    )
  end
end
