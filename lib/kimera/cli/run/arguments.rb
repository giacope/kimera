# frozen_string_literal: true

require_relative "../../operators"
require_relative "../../report/formats"
require_relative "../../scope/config"
require_relative "given"
require_relative "options"

class Kimera::CLI::Run::Arguments
  def initialize(table = Kimera::CLI::RunOptions::Usage.new, random: Random.new, formats: Kimera::Report::Formats.new)
    @table = table
    @random = random
    @formats = formats
  end

  def parse(argv)
    rest, given = @table.parse(argv, defaults.merge(Kimera::Config.parse(argv).options))
    Kimera::CLI::Run::Given.new(given, rest, @random, @formats).settings
  end

  private

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
      .merge(since_scope: "lines")
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
