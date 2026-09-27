# frozen_string_literal: true

require "open3"
require_relative "../execution/suite_env"

class Kimera::CLI::TestCommand
  LOADER = "ARGV.map { |f| File.expand_path(f) }.tap { ARGV.clear }.each { |f| require(f) }"
  MAX_LISTED = 10
  COUNT_LINE = /\d+ (?:failures?|examples?)\b/i
  SUMMARIES = [COUNT_LINE, /failed|Error\b/i].freeze
  RSPEC_RERUN = /^rspec (\S+) #/
  MINITEST_HEADER = /^\s*\d+\) (?:Failure|Error):\n(.+?)(?: \[[^\]]*\])?:$/
  CULPRITS = [RSPEC_RERUN, MINITEST_HEADER].freeze
  DRY_RUN = "require 'minitest'; Minitest.class_variable_set(:@@installed_at_exit, true); #{LOADER}; exit!(0)".freeze

  def initialize(framework, files, root:)
    @framework = framework
    @files = files
    @root = root
  end

  def baseline
    check(run, "Baseline: configured test suite is green") do |failure, output|
      ["✗", "Baseline: #{advice(failure)}#{failing(output)}"]
    end
  end

  def loading
    check(dry_run, "Test loading: every test file loads") do |failure|
      failure ? ["✗", "Test loading: #{failure}"] : ["!", "Test loading: Bundler is unavailable; not checked"]
    end
  end

  private

  def advice(failure)
    return "Bundler is unavailable; run your test suite, then retry" unless failure
    "#{failure} (fix it, then rerun `kimera doctor --check-baseline`)"
  end

  def check(command, passed)
    output, status = Open3.capture2e(Kimera::Execution::SUITE_ENV, *command, chdir: @root)
    status.success? ? ["✓", passed] : yield(summary(output), output)
  rescue Errno::ENOENT
    yield(nil)
  end

  def run = minitest? ? ruby(LOADER) : rspec

  def dry_run = minitest? ? ruby(DRY_RUN) : rspec("--dry-run")

  def failing(output)
    ids = culprits(output.to_s)
    return "" if ids.empty?
    "\n  failing tests:#{ids.first(MAX_LISTED).map { |id| "\n    #{id}" }.join}#{overflow(ids)}"
  end

  def overflow(ids) = (ids.size - MAX_LISTED).then { |more| more.positive? ? "\n    … and #{more} more" : "" }

  def culprits(output) = CULPRITS.flat_map { |pattern| output.scan(pattern).flatten }.uniq

  def summary(output)
    lines = output.lines.reverse
    SUMMARIES.lazy.filter_map { |pattern| lines.find { |line| line.match?(pattern) } }.first&.strip ||
      "test command failed"
  end

  def ruby(script) = ["bundle", "exec", "ruby", "-Itest", "-e", script, *@files]

  def rspec(*flags) = ["bundle", "exec", "rspec", *flags, *@files]

  def minitest? = @framework == "minitest"
end
