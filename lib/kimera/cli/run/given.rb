# frozen_string_literal: true

require_relative "../../error"
require_relative "../../scope/config"
require_relative "../../scope/file_set"
require_relative "settings"
require_relative "targets"

class Kimera::CLI::Run::Given
  SEEDS = 2**31
  DEFAULT_TESTS = ["spec/**/*_spec.rb"].freeze
  UNMEASURED = "needs the coverage baseline; drop --no-coverage"

  def initialize(flags, rest, random, formats)
    @flags = flags
    @rest = rest
    @random = random
    @formats = formats
  end

  def settings
    chosen = scoped.merge(attribution: attribution.mode, unit_tests: attribution.rules)
    require_coverage!("--attribution unit") if chosen[:attribution] == "unit"
    Kimera::CLI::Run::Settings.new(chosen.merge(flaky_runs: reruns).merge(seed: @flags[:seed]&.then { seed(it) }))
  end

  private

  def attribution = Kimera::Config::Attribution.new(@flags)

  def seed(value)
    return @random.rand(SEEDS) if value.to_s == "random"
    Integer(value.to_s, 10).tap { |seed| raise(ArgumentError) unless seed.between?(0, SEEDS - 1) }
  rescue ArgumentError
    raise(Kimera::UsageError, "--seed takes a whole number from 0 to #{SEEDS - 1}, or random; got #{value.inspect}")
  end

  def reruns
    value = @flags[:flaky_runs]
    runs = Integer(value.to_s, 10).tap { |count| raise(ArgumentError) if count.negative? }
    require_coverage!("--flaky-runs") if runs.positive?
    runs
  rescue ArgumentError
    raise(Kimera::UsageError, "--flaky-runs takes a whole number of reruns, got #{value.inspect}")
  end

  def require_coverage!(setting)
    raise(Kimera::UsageError, "#{setting} #{UNMEASURED}") if @flags[:coverage] == false
  end

  def scoped
    targets = Kimera::CLI::Run::Targets.new(@rest)
    formatted.merge(tests: tests(@flags[:cli_tests]), configured_tests: tests([]))
      .merge(paths: Kimera::FileSet.from_options(targets.paths, **@flags).to_a)
      .merge(lines: targets.lines).merge(arrays)
  end

  def formatted
    @flags.except(:cli_tests, :cli_unit_tests, :baseline_ignore).merge(format: @formats.normalize(@flags[:format]))
  end

  def tests(cli) = Kimera::Config::Precedence.new(cli, @flags[:tests]).chosen(DEFAULT_TESTS)

  def arrays
    { exclude: Array(@flags[:exclude]), ignore: Kimera::Config::Ignores.new(@flags).rules }
      .merge(isolate_when_covered_by: Array(@flags[:isolate_when_covered_by]), focus: Array(@flags[:focus]))
      .merge(methods: Array(@flags[:methods]))
  end
end
