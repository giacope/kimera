# frozen_string_literal: true

require_relative "../../execution/harness"
require_relative "../../execution/isolated"
require_relative "../../frameworks/adapter"
require_relative "../../report/progress"
require_relative "../../results/run_report"
require_relative "../../self_protection"
require_relative "sources"

class Kimera::CLI::Run::Pass
  def initialize(registry, options, adapter)
    @registry = registry
    @options = options
    @adapter = adapter
  end

  def call(remaining, session)
    report = with_adapter { perform(remaining) }.then { |judged| judged.described(@adapter.catalog(judged.test_ids)) }
    session.merge!(report)
    report
  end

  private

  def progress = @_progress ||= Kimera::Report::Progress.new(enabled: @options[:progress])

  def with_adapter
    yield
  ensure
    @adapter&.finish
  end

  def perform(remaining)
    warm
    run(remaining)
  end

  def harness = @_harness ||= Kimera::Execution::Harness.build(**settings)

  def files
    @_files ||= Kimera::CLI::Run::Sources.new.expand(
      @options[:tests], @options[:exclude_tests], "test", "check --tests"
    )
  end

  def settings
    base.merge({ hard_timeout: @options[:hard_timeout] }.compact)
  end

  def base
    { registry: @registry, adapter: @adapter, source_root: @options[:source_root] }
      .merge(soft_timeout: @options[:soft_timeout], leak_every: @options[:leak_every], jobs: @options[:jobs])
      .merge(isolate_db: @options[:isolate_db], progress: progress)
      .merge(@options.slice(:relative_timeout, :timeout_factor, :timeout_slack))
  end

  def warm
    if @options[:isolated] || @options[:coverage]
      harness.warm!(files)
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
    apart, together = split(remaining)
    return rejudged(harness.run(ids: together, label: "mutants")) if apart.empty?
    rejudged(harness.run(ids: together, label: "mutants (warm)")).merge(isolated.call(apart))
  end

  def rejudged(report)
    unjudged = report.errors
    return report if unjudged.empty? || @options[:rejudge] == false
    report.revise(isolation.rejudge(unjudged, label: "mutants (re-judged)"))
  end

  def judge(ids)
    isolation.verify!
    isolation.run(ids: ids, label: "mutants (isolated)")
  end

  def isolation
    @_isolation ||= Kimera::Execution::IsolatedExecution.new(**core, **limits)
  end

  def core
    { registry: @registry, root: @options[:source_root], tests: @adapter.test_ids }
      .merge(coverage: harness.coverage, progress: progress, jobs: @options[:jobs])
      .merge(framework: @options[:framework], test_files: files)
  end

  def limits = { hard_timeout: @options[:hard_timeout] }.compact

  def split(ids)
    patterns = Array(@options[:isolate_when_covered_by])
    ids.partition do |id|
      critical?(id) || patterns.any? { |pattern| matches?(harness.coverage, id, pattern) }
    end
  end

  def critical?(id) = Kimera::SelfProtection.critical?(@registry.index.fetch(id).file)

  def matches?(coverage, id, pattern)
    tests = coverage.fetch(id) { coverage.fetch(id.to_s, []) }
    tests.any? { |test| test.include?(pattern) }
  end
end
