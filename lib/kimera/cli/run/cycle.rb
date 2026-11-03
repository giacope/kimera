# frozen_string_literal: true

require_relative "../../execution/suite_env"
require_relative "bench"
require_relative "null_selection"
require_relative "../../incremental/session"
require_relative "../../incremental/stamp"
require_relative "aim"
require_relative "inline_ignores"
require_relative "../../scope/ignore_list"
require_relative "alerts"
require_relative "digest"
require_relative "narrowing"
require_relative "pass"
require_relative "route"
require_relative "sources"

class Kimera::CLI::Run::Cycle
  SETTINGS = %i[
    framework source_root tests exclude_tests exclude_test_names operators coverage isolated attribution unit_tests
    seed flaky_runs
    test_quality judge_isolated_only confirm_survivors
  ].freeze

  NARROWED = "not covered by the narrowed tests; a test outside --tests may cover it"

  def initialize(options, registry, digest:, alerts: Kimera::CLI::Run::Alerts.new)
    @options = options
    @registry = registry
    @digest = digest
    @alerts = alerts
  end

  def call(change = Kimera::CLI::Run::NullSelection.new, bench = Kimera::CLI::Run::Bench.new)
    @digest.verbose(@options) if @options[:verbose]
    todo, ignored = scope(change, change.ids(@registry))
    conclude(todo, ignored, session(todo, ignored, bench))
  end

  private

  def scope(change, selected)
    eligible = focus(Kimera::CLI::Run::Aim.new(@registry, @options).restrict(selected))
    resolution = Kimera::IgnoreList.new(@options[:ignore] + inline).resolve(@registry)
    ignored = resolution.ignored(eligible)
    notify(change, selected, ignored, resolution)
    [eligible - ignored, ignored]
  end

  def notify(change, selected, ignored, resolution)
    @alerts.anchors(resolution)
    @digest.announce(change, selected, ignored, files: @registry.files.size)
    @digest.evaluating(ignored) if @options[:evaluate_ignored]
  end

  def session(todo, ignored, bench)
    loaded = Kimera::Incremental::Session.from(@options[:session], stamp: stamp).pruned(@registry)
    perform(@options[:evaluate_ignored] ? todo + ignored : todo, loaded, bench)
  end

  def perform(todo, loaded, bench)
    remaining = todo.reject { |id| loaded.done?(id) }
    judged = remaining.empty? ? loaded : loaded.merged(harness(remaining, bench))
    path = @options[:session]
    judged.fingerprinted(@registry).save(path, meta: { "since" => @options[:since] }) if path
    judged
  end

  def conclude(todo, ignored, loaded)
    report = narrowed(loaded.report(todo, ignored, @registry)).counting(counted)
    @digest.emit(report, @registry, **emission)
    @options[:gate] == false ? 0 : @alerts.gate(report, @options.to_h.merge(narrowed: narrowing.narrowed?))
  end

  def narrowed(report)
    return report unless narrowing.narrowed?
    report.revise(report.uncovered.map { |result| result.narrowed(NARROWED) })
  end

  def emission
    { path: @options[:report], format: @options.to_h.fetch(:format, "text"), metadata: provenance }
      .merge(coverage: coverage, log: @options[:log], scope: narrowing.notes, summary: @options[:summary])
  end

  def stamp
    return unless @options[:session]
    settings = @options.to_h.slice(*SETTINGS, :require)
    Kimera::Incremental::Stamp.new(root: @options[:source_root], sources: @registry.files, settings: settings).to_s
  end

  def inline = Kimera::CLI::Run::InlineIgnores.new(@registry, root: @options[:source_root]).rules

  def narrowing(kind = Kimera::CLI::Run::Narrowing) = @_narrowing ||= kind.new(@options)

  def coverage = @options[:fail_on_no_coverage] || @options[:count_no_coverage] ? :list : :hint

  def counted = @options[:count_no_coverage] && !narrowing.narrowed? ? [:no_coverage] : []

  def focus(eligible)
    ids = Array(@options[:focus]).map { |token| @registry.keys.id(token) }
    return eligible if ids.empty?
    missing = ids - eligible
    missing.empty? ? ids : raise(Kimera::UsageError, "focused mutant(s) not in scope: #{missing.join(", ")}")
  end

  def provenance
    route = Kimera::CLI::Run::Route.new(@registry, @options)
    @options.to_h.slice(*SETTINGS, :jobs, :since, :count_no_coverage).transform_keys(&:to_s).merge(narrowing.provenance)
      .merge("judge_isolated_only" => route.judging?, "confirm_survivors" => route.confirming?)
  end

  def harness(remaining, bench, env: ENV, suite_env: Kimera::Execution::SuiteEnv.new(env))
    suite_env.install(@options[:seed], @options[:load_path])
    suite = bench.suite(@options[:framework], Array(@options[:exclude_test_names]))
    Kimera::CLI::Run::Pass.new(@registry, @options, suite, bench).call(remaining)
  end
end
