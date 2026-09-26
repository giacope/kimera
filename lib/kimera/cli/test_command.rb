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
    check(run, "Baseline: configured test suite is green") do |failure|
      if failure
        ["✗", "Baseline: #{failure} (fix it, then rerun `kimera doctor --check-baseline`)"]
      else
        ["✗", "Baseline: Bundler is unavailable; run your test suite, then retry"]
      end
    end
  end

  def loading
    check(dry_run, "Test loading: every test file loads") do |failure|
      failure ? ["✗", "Test loading: #{failure}"] : ["!", "Test loading: Bundler is unavailable; not checked"]
    end
  end

  private

  def check(command, passed)
    output, status = Open3.capture2e(*command, chdir: @root)
    status.success? ? ["✓", passed] : yield(summary(output))
  rescue Errno::ENOENT
    yield(nil)
  end

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
