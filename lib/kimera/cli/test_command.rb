# frozen_string_literal: true

require "open3"

class Kimera::CLI::TestCommand
  LOADER = "ARGV.map { |f| File.expand_path(f) }.tap { ARGV.clear }.each { |f| require(f) }"
  DRY_RUN = "require 'minitest'; Minitest.class_variable_set(:@@installed_at_exit, true); #{LOADER}; exit!(0)".freeze

  def initialize(framework, files, root:)
    @framework = framework
    @files = files
    @root = root
  end

  def baseline
    output, status = Open3.capture2e(*run, chdir: @root)
    return ["✓", "Baseline: configured test suite is green"] if status.success?
    ["✗", "Baseline: #{summary(output)} (fix it, then rerun `kimera doctor --check-baseline`)"]
  rescue Errno::ENOENT
    ["✗", "Baseline: Bundler is unavailable; run your test suite, then retry"]
  end

  def loading
    output, status = Open3.capture2e(*dry_run, chdir: @root)
    return ["✓", "Test loading: every test file loads"] if status.success?
    ["✗", "Test loading: #{summary(output)}"]
  rescue Errno::ENOENT
    ["!", "Test loading: Bundler is unavailable; not checked"]
  end

  private

  def run = minitest? ? ruby(LOADER) : rspec

  def dry_run = minitest? ? ruby(DRY_RUN) : rspec("--dry-run")

  def summary(output)
    output.lines.reverse.find { |line| line.match?(/\d+ failures?|\d+ examples?|failed|Error\b/i) }&.strip ||
      "test command failed"
  end

  def ruby(script) = ["bundle", "exec", "ruby", "-Itest", "-e", script, *@files]

  def rspec(*flags) = ["bundle", "exec", "rspec", *flags, *@files]

  def minitest? = @framework == "minitest"
end
