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
require_relative "mirror_database"
require_relative "null_progress"
require_relative "numbered_databases"
require_relative "parent_connections"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedExecution
  include Kimera::Execution::IsolatedScheduling
  include Kimera::Execution::IsolatedVerdict
  include Kimera::Execution::IsolatedWatchdog

  DEFAULT_HARD_TIMEOUT = 300.0
  COVERED = [Kimera::Execution::BlockUse::REASON, Kimera::Execution::MacroLambdas::KEPT].freeze

  def initialize(registry:, root:, tests:, **options)
    @registry = registry
    @root = root
    @tests = tests
    @options = options
  end

  def verify!(ids = nil)
    tests = ids ? needed(ids) : plan.suite
    return if tests.empty?
    progress.note("isolated baseline (unmutated mirror)")
    outcome = with_mirror { |mirror| verdict(mirror, tests) }
    return if outcome.status == :survived
    mirror = Kimera::Execution::BaselineFailure::Mirror.new(outcome.explain, Kimera::Execution::IsolatedPlan::MIRROR_HINT)
    raise(Kimera::Execution::BaselineFailure, mirror.to_s)
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

  def with_mirror(&)
    ready!
    super
  end

  def ready!
    Kimera::Execution::ParentConnections.new.release!
    return if @_ready || jobs == 1
    @_ready = true
    databases = Kimera::Execution::NumberedDatabases.new
    return (1...jobs).each { |slot| databases.prepare(slot) } if databases.numbered?
    Kimera::Execution::MirrorDatabase.new(nil).prepare(1...jobs)
  end

  def progress = @options.fetch(:progress, Kimera::Execution::NullProgress::NONE)

  def limit = @options.fetch(:hard_timeout, DEFAULT_HARD_TIMEOUT)

  def needed(ids)
    index = plan.registry.index
    plan.suite & ids.flat_map { |id| index.key?(id) ? Array(plan.tests(id, index[id])) : [] }
  end

  def jobs = @_jobs ||= [Integer(@options.fetch(:jobs, 1)), 1].max

  def plan
    @_plan ||= Kimera::Execution::IsolatedPlan.new(
      registry: @registry, root: @root, tests: @tests,
      coverage: @options.fetch(:coverage, {}), timings: @options.fetch(:timings, {}),
      framework: @options.fetch(:framework, "rspec"),
      test_files: @options.fetch(:test_files, []), filter: @options[:filter], seed: @options[:seed],
      quality: @options[:test_quality], test_paths: @options[:test_paths]
    )
  end

  def announce(count, label)
    progress.note("re-judging #{count} mutant(s) the warm pass could not judge, each in a fresh mirror")
    progress.start(count, label)
  end

  def noted(result, warm)
    judged = covered?(warm) ? covered(result, warm) : result
    judged.tap { judged.note = "judged in a fresh isolated mirror; the warm pass could not: #{warm.detail}" }
  end

  def covered?(warm) = COVERED.include?(plan.registry.index.fetch(warm.mutant_id).revisit)

  def covered(result, warm)
    kept = result.killed? || warm.status == :survived ? result : warm.dup
    kept.tap { kept.covering_tests = [*warm.covering_tests, *result.failing_tests].uniq }
  end

  def report(ids)
    Kimera::RunReport.new(
      results: (jobs > 1 ? concurrently(ids) : serially(ids)),
      leaks: [], registry: plan.registry
    )
  end
end
