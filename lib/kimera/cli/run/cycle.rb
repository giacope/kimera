# frozen_string_literal: true

require_relative "../../execution/suite_env"
require_relative "../../incremental/selection"
require_relative "../../incremental/session"
require_relative "../../incremental/stamp"
require_relative "aim"
require_relative "inline_ignores"
require_relative "digest"
require_relative "narrowing"
require_relative "pass"
require_relative "sources"

class Kimera::CLI::Run::Cycle
  SETTINGS = %i[framework source_root tests exclude_tests operators coverage isolated].freeze

  def initialize(options, registry, changed, digest:)
    @options = options
    @registry = registry
    @changed = changed
    @digest = digest
  end

  def call
    @digest.verbose(@options) if @options[:verbose]
    @registry.narrow!(@changed) if @changed
    scope(@changed && Kimera::Incremental::Selection.select(@registry, @changed))
  end

  private

  def scope(selected)
    eligible = focus(Kimera::CLI::Run::Aim.new(@registry, @options).restrict(selected || @registry.index.keys))
    resolution = Kimera::IgnoreList.resolve(@registry, @options[:ignore] + inline)
    ignored = resolution.ids & eligible
    notify(selected, ignored, resolution)
    session(eligible - ignored, ignored)
  end

  def notify(selected, ignored, resolution)
    @digest.anchors(resolution)
    @digest.announce(selected, ignored, files: @registry.files.size, since: @options[:since])
    @digest.evaluating(ignored) if @options[:evaluate_ignored]
  end

  def session(todo, ignored)
    loaded = Kimera::Incremental::Session.from(@options[:session], registry: @registry, stamp: stamp)
    conclude(todo, ignored, perform(@options[:evaluate_ignored] ? todo + ignored : todo, loaded))
  end

  def perform(todo, loaded)
    remaining = todo.reject { |id| loaded.done?(id) }
    judged = remaining.empty? ? loaded : loaded.merged(harness(remaining))
    path = @options[:session]
    judged.save(path, registry: @registry, meta: { "since" => @options[:since] }) if path
    judged
  end

  def conclude(todo, ignored, loaded)
    report = loaded.report(todo, ignored, @registry)
    @digest.emit(report, @registry, **emission)
    @options[:gate] == false ? 0 : @digest.gate(report, @options)
  end

  def emission
    { path: @options[:report], format: @options.fetch(:format, "text"), metadata: provenance }
      .merge(coverage: coverage, log: @options[:log], scope: narrowing.note, summary: @options[:summary])
  end

  def stamp
    return unless @options[:session]
    settings = @options.slice(*SETTINGS, :require)
    Kimera::Incremental::Stamp.new(root: @options[:source_root], sources: @registry.files, settings: settings).to_s
  end

  def inline = Kimera::CLI::Run::InlineIgnores.new(@registry, root: @options[:source_root]).rules

  def narrowing = @_narrowing ||= Kimera::CLI::Run::Narrowing.new(@options)

  def coverage = @options[:fail_on_no_coverage] ? :list : :hint

  def focus(eligible)
    ids = Array(@options[:focus]).map { |token| @registry.keys.id(token) }
    return eligible if ids.empty?
    missing = ids - eligible
    missing.empty? ? ids : raise(Kimera::UsageError, "focused mutant(s) not in scope: #{missing.join(", ")}")
  end

  def provenance
    @options.slice(*SETTINGS, :jobs, :since).transform_keys(&:to_s).merge(narrowing.provenance)
  end

  def harness(remaining, env: ENV)
    env.update(Kimera::Execution::SUITE_ENV)
    adapter = Kimera::Frameworks::ADAPTERS.load(@options[:framework])
    Kimera::CLI::Run::Pass.new(@registry, @options, adapter).call(remaining)
  end
end
