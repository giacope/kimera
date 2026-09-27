# frozen_string_literal: true

require_relative "../../execution/suite_env"
require_relative "../../incremental/selection"
require_relative "../../incremental/session"
require_relative "digest"
require_relative "narrowing"
require_relative "pass"
require_relative "sources"

class Kimera::CLI::Run::Cycle
  def initialize(options, registry, changed, digest:)
    @options = options
    @registry = registry
    @changed = changed
    @digest = digest
  end

  def call
    @digest.verbose(@options) if @options[:verbose]
    scope(@changed && Kimera::Incremental::Selection.select(@registry, @changed))
  end

  private

  def scope(selected)
    eligible = focus(selected || @registry.each.map { |mutant, _| mutant.id })
    ignored = Kimera::IgnoreList.ids(@registry, @options[:ignore]) & eligible
    notify(selected, ignored)
    session(eligible - ignored, ignored)
  end

  def notify(selected, ignored)
    @digest.stale(@registry, @options[:ignore])
    @digest.announce(selected, ignored, files: @registry.files.size, since: @options[:since])
  end

  def session(todo, ignored)
    loaded = Kimera::Incremental::Session.load(@options[:session], registry: @registry)
    perform(todo, loaded)
    conclude(todo, ignored, loaded)
  end

  def perform(todo, loaded)
    remaining = todo.reject { |id| loaded.done?(id) }
    harness(remaining, loaded) unless remaining.empty?
    path = @options[:session]
    loaded.save(path, registry: @registry, meta: { "since" => @options[:since] }) if path
  end

  def conclude(todo, ignored, loaded)
    report = loaded.report(todo, ignored, @registry)
    @digest.emit(report, @registry, **emission)
    @options[:gate] == false ? 0 : @digest.gate(report, @options)
  end

  def emission
    { path: @options[:report], format: @options.fetch(:format, "text"), metadata: provenance }
      .merge(coverage: coverage, log: @options[:log], scope: narrowing.note)
  end

  def narrowing = @_narrowing ||= Kimera::CLI::Run::Narrowing.new(@options)

  def coverage = @options[:fail_on_no_coverage] ? :list : :hint

  def focus(eligible)
    ids = Array(@options[:focus]).map { |token| @registry.keys.id(token) }
    return eligible if ids.empty?
    missing = ids - eligible
    missing.empty? ? ids : raise(Kimera::UsageError, "focused mutant(s) not in scope: #{missing.join(", ")}")
  end

  def provenance
    @options.slice(:framework, :source_root, :tests, :exclude_tests, :operators, :coverage, :isolated, :jobs)
      .transform_keys(&:to_s).merge(narrowing.provenance)
  end

  def harness(remaining, loaded, env: ENV)
    env.update(Kimera::Execution::SUITE_ENV)
    adapter = Kimera::Frameworks::Adapter.load(@options[:framework])
    Kimera::CLI::Run::Pass.new(@registry, @options, adapter).call(remaining, loaded)
  end
end
