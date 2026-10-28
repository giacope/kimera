# frozen_string_literal: true

require_relative "../../operators"
require_relative "../../report/formats"
require_relative "../../scope/config"
require_relative "../../scope/file_set"
require_relative "options"
require_relative "targets"

class Kimera::CLI::Run::Arguments
  SEEDS = 2**31
  DEFAULT_TESTS = ["spec/**/*_spec.rb"].freeze

  def initialize(table = Kimera::CLI::RunOptions::Usage.new, random: Random.new, formats: Kimera::Report::Formats.new)
    @table = table
    @random = random
    @formats = formats
  end

  def parse(argv)
    rest, options = @table.parse(argv, defaults.merge(Kimera::Config.parse(argv).options))
    finish(options, rest)
  end

  private

  def finish(options, rest)
    validate(options)
    options.except(:cli_tests, :cli_unit_tests, :baseline_ignore)
      .merge(scoped(options, rest)).merge(attributed(options)).merge(seeded(options))
  end

  def validate(options) = @formats.normalize(options[:format])

  def attributed(options)
    settings = Kimera::Config::Attribution.new(options).settings
    measured(options, "--attribution unit") if settings[:attribution] == "unit"
    settings
  end

  def seeded(options)
    runs = reruns(options[:flaky_runs])
    measured(options, "--flaky-runs") if runs.positive?
    { seed: options[:seed]&.then { |value| seed(value) }, flaky_runs: runs }
  end

  def seed(value)
    return @random.rand(SEEDS) if value.to_s == "random"
    Integer(value.to_s, 10).tap { |seed| raise(ArgumentError) unless seed.between?(0, SEEDS - 1) }
  rescue ArgumentError
    raise(Kimera::UsageError, "--seed takes a whole number from 0 to #{SEEDS - 1}, or random; got #{value.inspect}")
  end

  def reruns(value)
    Integer(value.to_s, 10).tap { |runs| raise(ArgumentError) if runs.negative? }
  rescue ArgumentError
    raise(Kimera::UsageError, "--flaky-runs takes a whole number of reruns, got #{value.inspect}")
  end

  def measured(options, setting)
    return unless options[:coverage] == false
    raise(Kimera::UsageError, "#{setting} needs the coverage baseline; drop --no-coverage")
  end

  def scoped(options, rest)
    targets = Kimera::CLI::Run::Targets.new(rest)
    { tests: tests(options[:cli_tests], options), configured_tests: tests([], options) }
      .merge(paths: Kimera::FileSet.from_options(targets.paths, options).to_a)
      .merge(lines: targets.lines).merge(arrays(options))
  end

  def tests(cli, options)
    Kimera::Config::Precedence.new(cli, options[:tests]).chosen(DEFAULT_TESTS)
  end

  def arrays(options)
    { exclude: Array(options[:exclude]), ignore: Kimera::Config::Ignores.new(options).rules }
      .merge(isolate_when_covered_by: Array(options[:isolate_when_covered_by]), focus: Array(options[:focus]))
      .merge(methods: Array(options[:methods]))
  end

  def defaults
    core.merge(gates).merge(scope)
  end

  def core
    { framework: "rspec", source_root: ".", tests: [] }
      .merge(paths: nil, operators: Kimera::Operators.build.map(&:key), soft_timeout: 5.0)
      .merge(hard_timeout: nil, registry: nil)
      .merge(relative_timeout: true, timeout_factor: nil, timeout_slack: nil)
      .merge(report: Kimera::CLI::ReportFile.default.to_s, format: "text", focus: [], gate: true, coverage: true)
      .merge(require: [])
  end

  def gates
    { since: nil, session: nil, max_survivors: nil }.merge(max_ignored: nil, max_errors: 0, jobs: 1)
      .merge(evaluate_ignored: false, baseline: nil)
  end

  def scope
    { exclude: [], exclude_tests: [], config: nil }.merge(exclude_test_names: [])
      .merge(ignore: [], isolate_db: false, isolated: false, rejudge: true)
      .merge(fail_on_no_coverage: false, count_no_coverage: true, judge_isolated_only: nil)
      .merge(confirm_survivors: nil)
      .merge(progress: nil, color: nil, quiet: false, verbose: false, log: nil)
      .merge(pidfile: nil, summary: nil)
      .merge(isolate_when_covered_by: [], methods: [])
      .merge(cli_tests: [], attribution: "any", unit_tests: {}, cli_unit_tests: [], seed: nil, flaky_runs: 0)
      .merge(test_quality: false, reuse_coverage: false)
  end
end
