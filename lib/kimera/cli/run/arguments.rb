# frozen_string_literal: true

require_relative "../../operators"
require_relative "../../report/formats"
require_relative "../../scope/config"
require_relative "../../scope/file_set"
require_relative "options"
require_relative "targets"

class Kimera::CLI::Run::Arguments
  def parse(argv)
    options = defaults.merge(Kimera::Config.parse(argv))
    finish(options, Kimera::CLI::RunOptions::OPTIONS.parse(argv, options))
  end

  private

  def finish(options, rest)
    validate(options)
    options.except(:cli_tests, :cli_unit_tests, :baseline_ignore)
      .merge(scoped(options, rest)).merge(attributed(options))
  end

  def validate(options) = Kimera::Report::Formats.new.normalize(options[:format])

  def attributed(options)
    mode = Kimera::Config.attribution(options[:attribution])
    measured(options, "--attribution unit") if mode == "unit"
    cli = Array(options[:cli_unit_tests])
    { attribution: mode, unit_tests: Kimera::Config.unit_tests(cli.empty? ? options[:unit_tests] : cli) }
  end

  def measured(options, setting)
    return unless options[:coverage] == false
    raise(Kimera::UsageError, "#{setting} needs the coverage baseline; drop --no-coverage")
  end

  def scoped(options, rest)
    targets = Kimera::CLI::Run::Targets.new(rest)
    { tests: tests(options[:cli_tests], options), configured_tests: tests([], options) }
      .merge(paths: Kimera::Config.prefer(targets.paths, options[:paths], Kimera::FileSet::DEFAULT_GLOBS))
      .merge(lines: targets.lines).merge(arrays(options))
  end

  def tests(cli, options) = Kimera::Config.prefer(cli, options[:tests], Kimera::CLI::RunOptions::DEFAULT_TESTS)

  def arrays(options)
    { exclude: Array(options[:exclude]), ignore: Kimera::Config.ignores(options) }
      .merge(isolate_when_covered_by: Array(options[:isolate_when_covered_by]), focus: Array(options[:focus]))
      .merge(methods: Array(options[:methods]))
  end

  def defaults
    core.merge(gates).merge(scope)
  end

  def core
    { framework: "rspec", source_root: ".", tests: [] }
      .merge(paths: nil, operators: Kimera::Operators::DEFAULT_KEYS, soft_timeout: 5.0)
      .merge(hard_timeout: nil, registry: nil)
      .merge(relative_timeout: true, timeout_factor: nil, timeout_slack: nil)
      .merge(report: Kimera::CLI::ReportFile::DEFAULT, format: "text", focus: [], gate: true, coverage: true)
      .merge(require: [])
  end

  def gates
    { since: nil, session: nil, max_survivors: nil }.merge(max_ignored: nil, max_errors: 0, jobs: 1)
      .merge(evaluate_ignored: false, baseline: nil)
  end

  def scope
    { exclude: [], exclude_tests: [], config: nil }
      .merge(ignore: [], isolate_db: false, isolated: false, rejudge: true)
      .merge(fail_on_no_coverage: false, count_no_coverage: false)
      .merge(progress: nil, color: nil, quiet: false, verbose: false, log: nil)
      .merge(pidfile: nil, summary: nil)
      .merge(isolate_when_covered_by: [], methods: [])
      .merge(cli_tests: [], attribution: "any", unit_tests: {}, cli_unit_tests: [])
  end
end
