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
    report = with_adapter { perform(remaining) }
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

  def harness = @_harness ||= Kimera::Execution::Harness.new(**settings)

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
  end

  def warm
    if @options[:isolated] || @options[:coverage]
      harness.warm!(files)
    else
      harness.without_coverage!(files)
    end
  end

  def run(remaining)
    isolated = ->(ids) { isolation.run(ids: ids, label: "mutants (isolated)") }
    return isolated.call(remaining) if @options[:isolated]
    pooled(remaining, isolated)
  end

  def pooled(remaining, isolated)
    apart, together = split(remaining)
    return harness.run(ids: together, label: "mutants") if apart.empty?
    harness.run(ids: together, label: "mutants (warm)").merge(isolated.call(apart))
  end

  def isolation
    Kimera::Execution::IsolatedExecution.new(**core, **{ hard_timeout: @options[:hard_timeout] }.compact)
  end

  def core
    { registry: @registry, root: @options[:source_root], tests: @adapter.test_ids }
      .merge(coverage: harness.coverage, progress: progress, jobs: @options[:jobs])
      .merge(framework: @options[:framework], test_files: files)
  end

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
