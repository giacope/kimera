# frozen_string_literal: true

require_relative "../../execution/harness"
require_relative "../../execution/test_filter"
require_relative "../../frameworks/suite"
require_relative "../../frameworks/test_task"
require_relative "../../incremental/coverage_cache"
require_relative "../../report/progress"
require_relative "../../results/run_report"
require_relative "bench"
require_relative "route"
require_relative "sources"

class Kimera::CLI::Run::Pass
  def initialize(registry, options, adapter, bench = Kimera::CLI::Run::Bench.new)
    @registry = registry
    @options = options
    @adapter = adapter
    @bench = bench
  end

  def call(remaining)
    with_adapter { harness.noted(perform(remaining)).annotate(**suite) }
      .then { |judged| judged.annotate(tests: @adapter[*judged.notes.test_ids].to_h) }
  end

  private

  def progress(kind = Kimera::Report::Progress) = @_progress ||= kind.new(enabled: @options[:progress])

  def with_adapter
    yield
  ensure
    @adapter&.hooks&.finish
  end

  def perform(remaining)
    warm(remaining)
    run(remaining)
  end

  def suite = @options[:test_quality] ? { suite: @adapter.test_ids } : {}

  def filter
    @_filter ||=
      if @options[:attribution] == "unit"
        filters.from_rules(@options[:unit_tests], registry: @registry, adapter: @adapter, root: @options[:source_root])
      else
        filters.build(registry: @registry, adapter: @adapter, root: @options[:source_root])
      end
  end

  def filters = Kimera::Execution::TestFilter

  def harness = @_harness ||= @bench.harness(**settings)

  def files(sources = Kimera::CLI::Run::Sources)
    @_files ||= sources.new.tests(@options[:tests], @options[:exclude_tests])
  end

  def settings = base.merge({ hard_timeout: @options[:hard_timeout] }.compact)

  def base
    { registry: @registry, adapter: @adapter, source_root: @options[:source_root] }
      .merge(soft_timeout: @options[:soft_timeout], jobs: @options[:jobs])
      .merge(isolate_db: @options[:isolate_db], progress: progress, filter: filter)
      .merge(@options.to_h.slice(:relative_timeout, :timeout_factor, :timeout_slack, :seed, :flaky_runs, :test_quality))
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
    deferred(rejudged(harness.run(ids: together, label: "mutants (warm)"))).revise(isolated.call(apart))
  end

  def deferred(report)
    pending = report.select { |result| result.status?(:isolated_only) }.to_h(&:entry).keys
    return report if pending.empty? || !route.judging?
    report.revise(judge(pending))
  end

  def route(kind = Kimera::CLI::Run::Route) = @_route ||= kind.new(@registry, @options)

  def cache(kind = Kimera::Incremental::CoverageCache)
    sources = -> { Kimera::FileSet.new(@options[:paths], exclude: @options[:exclude]).relative_to(@options[:source_root]) }
    @_cache ||= kind.new(registry: @registry, options: @options, sources: sources)
  end

  def rejudged(report)
    unjudged = report.select { |result| result.status?(:harness_error) } + revisited(report)
    return report if unjudged.empty?
    return report.revise(unjudged) if @options[:rejudge] == false
    report.revise(isolation.rejudge(unjudged, label: "mutants (re-judged)"))
  end

  def revisited(report)
    reason = ->(result) { result.from(@registry.index).reasons(Kimera::Reason.revisiting).first }
    %i[survived no_coverage].flat_map { |status| report.select { |result| result.status?(status) } }
      .filter_map { |result| reason.call(result)&.then { result.with(detail: it) } }
  end

  def judge(ids)
    isolation.verify!(ids)
    isolation.run(ids: ids, label: "mutants (isolated)")
  end

  def isolation
    @_isolation ||= harness.isolated(**core, **limits)
  end

  def core
    { registry: @registry, root: @options[:source_root], tests: @adapter.test_ids }
      .merge(progress: progress, jobs: @options[:jobs])
      .merge(framework: @options[:framework], test_files: files, filter: filter, test_paths: paths, warnings: warnings)
  end

  def paths = ->(id) { @adapter[id].file }

  def warnings
    @options[:framework] == "minitest" ? Kimera::Frameworks::TestTask.new(@options[:source_root]).flags : []
  end

  def limits = @options.to_h.slice(:seed, :test_quality).merge({ hard_timeout: @options[:hard_timeout] }.compact)
end
