# frozen_string_literal: true

require_relative "../../operators"
require_relative "../../report/formats"
require_relative "../../scope/config"
require_relative "../../scope/file_set"
require_relative "options"

class Kimera::CLI::Run::Arguments
  def parse(argv)
    options = defaults.merge(Kimera::Config.parse(argv))
    finish(options, Kimera::CLI::RunOptions::OPTIONS.parse(argv, options))
  end

  private

  def finish(options, rest)
    validate(options)
    options.except(:cli_tests, :baseline_ignore).merge(scoped(options, rest))
  end

  def validate(options) = Kimera::Report::Formats.new.normalize(options[:format])

  def scoped(options, rest)
    {
      tests: tests(options[:cli_tests], options), configured_tests: tests([], options),
      paths: Kimera::Config.prefer(rest, options[:paths], Kimera::FileSet::DEFAULT_GLOBS)
    }.merge(arrays(options))
  end

  def tests(cli, options) = Kimera::Config.prefer(cli, options[:tests], Kimera::CLI::RunOptions::DEFAULT_TESTS)

  def arrays(options)
    { exclude: Array(options[:exclude]), ignore: Kimera::Config.ignores(options) }
      .merge(isolate_when_covered_by: Array(options[:isolate_when_covered_by]), focus: Array(options[:focus]))
  end

  def defaults
    core.merge(gates).merge(scope)
  end

  def core
    { framework: "rspec", source_root: ".", tests: [] }
      .merge(paths: nil, operators: Kimera::Operators::DEFAULT_KEYS, soft_timeout: 5.0)
      .merge(hard_timeout: nil, leak_every: 10, registry: nil)
      .merge(report: nil, format: "text", focus: [], gate: true, coverage: true, require: [])
  end

  def gates
    { since: nil, session: nil, max_survivors: nil }.merge(max_ignored: nil, max_errors: 0, jobs: 1)
      .merge(evaluate_ignored: false, baseline: nil)
  end

  def scope
    { exclude: [], exclude_tests: [], config: nil }
      .merge(ignore: [], isolate_db: false, isolated: false, rejudge: true)
      .merge(fail_on_no_coverage: false, progress: nil, color: nil, quiet: false, verbose: false, log: nil)
      .merge(pidfile: nil)
      .merge(isolate_when_covered_by: [])
      .merge(cli_tests: [])
  end
end
