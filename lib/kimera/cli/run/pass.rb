# frozen_string_literal: true

require_relative "../../execution/harness"
require_relative "../../execution/isolated"
require_relative "../../execution/test_filter"
require_relative "../../frameworks/suite"
require_relative "../../frameworks/test_task"
require_relative "../../incremental/coverage_cache"
require_relative "../../report/progress"
require_relative "../../results/run_report"
require_relative "route"
require_relative "sources"

class Kimera::CLI::Run::Pass
  def initialize(registry, options, adapter)
    @registry = registry
    @options = options
    @adapter = adapter
  end

  def call(remaining)
    with_adapter { perform(remaining).then { |judged| judged.annotate(flaky: harness.flakes&.to_h, suite: suite) } }
      .then { |judged| judged.described(@adapter.catalog(judged.test_ids)) }
  end

  private

  def progress = @_progress ||= Kimera::Report::Progress.new(enabled: @options[:progress])

  def with_adapter
    yield
  ensure
    @adapter&.finish
  end

  def perform(remaining)
    warm(remaining)
    run(remaining)
  end

  def suite = @options[:test_quality] ? @adapter.test_ids : nil

  def filter
    @_filter ||= Kimera::Execution::TestFilter.build(
      registry: @registry, rules: @options[:attribution] == "unit" ? @options[:unit_tests] : nil,
      adapter: @adapter, root: @options[:source_root]
    )
  end

  def harness = @_harness ||= Kimera::Execution::Harness.build(**settings)

  def files
    @_files ||= Kimera::CLI::Run::Sources.new.tests(@options[:tests], @options[:exclude_tests])
  end

  def settings
    base.merge({ hard_timeout: @options[:hard_timeout] }.compact)
  end

  def base
    { registry: @registry, adapter: @adapter, source_root: @options[:source_root] }
      .merge(soft_timeout: @options[:soft_timeout], jobs: @options[:jobs])
      .merge(isolate_db: @options[:isolate_db], progress: progress, filter: filter)
      .merge(@options.slice(:relative_timeout, :timeout_factor, :timeout_slack, :seed, :flaky_runs, :test_quality))
      .merge(confirm_survivors: route.confirming?, measured: cache.method(:measured))
  end

  def warm(remaining)
    if @options[:isolated] || @options[:coverage]
      harness.warm!(files, scope: remaining)
      cache.keep(harness, @adapter)
    else
      harness.without_coverage!(files)
    end
  end

  def run(remaining)
    isolated = ->(ids) { judge(ids) }
    return isolated.call(remaining) if @options[:isolated]
    pooled(remaining, isolated)
  end

  def pooled(remaining, isolated)
    apart, together = route.split(remaining) { harness.coverage }
    return deferred(rejudged(harness.run(ids: together, label: "mutants"))) if apart.empty?
    deferred(rejudged(harness.run(ids: together, label: "mutants (warm)"))).merge(isolated.call(apart))
  end

  def deferred(report)
    pending = report.statuses(:isolated_only).map(&:mutant_id)
    return report if pending.empty? || !route.judging?
    report.revise(judge(pending).results)
  end

  def route = @_route ||= Kimera::CLI::Run::Route.new(@registry, @options)

  def cache
    sources = -> { Kimera::FileSet.new(@options[:paths], exclude: @options[:exclude]).relative_to(@options[:source_root]) }
    @_cache ||= Kimera::Incremental::CoverageCache.new(registry: @registry, options: @options, sources: sources)
  end

  def rejudged(report)
    unjudged = report.errors + revisited(report)
    return report if unjudged.empty?
    return report.revise(unjudged) if @options[:rejudge] == false
    report.revise(isolation.rejudge(unjudged, label: "mutants (re-judged)"))
  end

  def revisited(report)
    (report.survived + report.uncovered).filter_map do |result|
      reason = @registry.index.fetch(result.mutant_id).revisit
      result.dup.tap { |copy| copy.detail = reason } if reason
    end
  end

  def judge(ids)
    isolation.verify!(ids)
    isolation.run(ids: ids, label: "mutants (isolated)")
  end

  def isolation
    @_isolation ||= Kimera::Execution::IsolatedExecution.new(**core, **limits)
  end

  def core
    { registry: @registry, root: @options[:source_root], tests: @adapter.test_ids }
      .merge(coverage: harness.coverage, timings: harness.timings, progress: progress, jobs: @options[:jobs])
      .merge(framework: @options[:framework], test_files: files, filter: filter, test_paths: paths, warnings: warnings)
  end

  def paths = ->(id) { @adapter.test_file(id).to_s }

  def warnings
    @options[:framework] == "minitest" ? Kimera::Frameworks::TestTask.new(@options[:source_root]).flags : []
  end

  def limits = @options.slice(:seed, :test_quality).merge({ hard_timeout: @options[:hard_timeout] }.compact)
end
