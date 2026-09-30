# frozen_string_literal: true

require "open3"
require_relative "../execution/suite_env"
require_relative "../listing"
require_relative "test_shard"

class Kimera::CLI::TestCommand
  LOADER = "ARGV.map { |f| File.expand_path(f) }.tap { ARGV.clear }.each { |f| require(f) }"
  COUNT_LINE = /\d+ (?:failures?|examples?)\b/i
  SUMMARIES = [COUNT_LINE, /failed|Error\b/i].freeze
  RSPEC_RERUN = /^rspec (\S+) #/
  MINITEST_HEADER = /^\s*(?:\d+\) )?(?:Failure|Error):\n(.+?)(?: \[[^\]]*\])?:$/
  CULPRITS = [RSPEC_RERUN, MINITEST_HEADER].freeze
  OUTSIDE = "occurred outside of examples"
  CAUSE = /^(\w+(?:::\w+)*(?:Error|Exception)):\n\s+(\S.*)$/
  NO_FAILURES = /\b0 failures(?:, 0 errors\b|\z)/
  QUIET_EXIT = " (it exited non-zero with no failing test: a coverage floor such as SimpleCov's " \
    "minimum_coverage? Skip it when ENV[\"KIMERA\"] is set)"
  DRY_RUN = "require 'minitest'; Minitest.class_variable_set(:@@installed_at_exit, true); #{LOADER}; exit!(0)".freeze
  SHARED = "red split across %d processes (jobs: %d), green in one: the suite shares state " \
    "between workers (a directory, file or port), which can turn `kimera run`'s baseline red; " \
    "use jobs: 1 until each test has its own"

  def initialize(framework, files, root:, jobs: 1)
    @framework = framework
    @files = files
    @root = root
    @jobs = jobs
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

  def baselines
    serial = baseline
    serial.first == "✓" && @jobs > 1 ? [serial, parallel(@jobs)] : [serial]
  end

  def parallel(jobs)
    red = shards(jobs).reject { |_output, status| status.success? }
    return ["✓", "Parallel baseline: green split across #{jobs} processes too (jobs: #{jobs})"] if red.empty?
    ["!", "Parallel baseline: #{format(SHARED, jobs, jobs)}#{failing(red.map(&:first).join)}"]
  end

  private

  def advice(failure)
    return "Bundler is unavailable; run your test suite, then retry" unless failure
    "#{failure} (fix it, then rerun `kimera doctor --check-baseline`)"
  end

  def check(command, passed)
    output, status = capture(command)
    status.success? ? ["✓", passed] : yield(summary(output), output)
  rescue Errno::ENOENT
    yield(nil)
  end

  def capture(command) = Open3.capture2e(Kimera::Execution::SUITE_ENV, *command, chdir: @root)

  def shards(jobs) = Array.new(jobs) { |index| Thread.new { capture(shard(index, jobs)) } }.map(&:value)

  def shard(index, count) = ["bundle", "exec", "ruby", *Kimera::CLI::TestShard.argv(@framework, index, count), *@files]

  def run = minitest? ? ruby(LOADER) : rspec

  def dry_run = minitest? ? ruby(DRY_RUN) : rspec("--dry-run")

  def failing(output)
    ids = culprits(output.to_s)
    return "" if ids.empty?
    "\n  failing tests:#{Kimera::Listing.lines(ids, "    ")}"
  end

  def culprits(output) = CULPRITS.flat_map { |pattern| output.scan(pattern).flatten }.uniq

  def summary(output) = headline(output).then { |line| "#{line}#{reason(output, line)}" }

  def headline(output)
    lines = output.lines.reverse
    SUMMARIES.lazy.filter_map { |pattern| lines.find { |line| line.match?(pattern) } }.first&.strip ||
      "test command failed"
  end

  def reason(output, line)
    return QUIET_EXIT if line.match?(NO_FAILURES)
    cause = output.match(CAUSE) if output.include?(OUTSIDE)
    cause ? " (#{cause.captures.join(": ")})" : ""
  end

  def ruby(script) = ["bundle", "exec", "ruby", "-Itest", "-e", script, *@files]

  def rspec(*flags) = ["bundle", "exec", "rspec", *flags, *@files]

  def minitest? = @framework == "minitest"
end
