# frozen_string_literal: true

require_relative "argv"
require_relative "flag"
require_relative "run"

class Kimera::CLI::CI
  DEFAULTS = [
    [%w[--max-survivors], %w[--max-survivors 0]],
    [%w[--fail-on-no-coverage --no-fail-on-no-coverage], %w[--fail-on-no-coverage]],
    [%w[--format], %w[--format github]]
  ].freeze
  BRANCHES = %w[GITHUB_BASE_REF CI_MERGE_REQUEST_TARGET_BRANCH_NAME BUILDKITE_PULL_REQUEST_BASE_BRANCH].freeze
  LOOKED = ["--since", "KIMERA_BASE", *BRANCHES].join(", ")
  UNGATED = "a full run leaves class-body DSL (validations, associations, callbacks) isolated_only: unjudged " \
    "and ungated; pass --judge-isolated-only to judge them all (hours on a Rails app)"
  BANNER = "Usage: kimera ci [paths...] [options]\n" \
    "kimera run with gate defaults: --max-survivors 0 --fail-on-no-coverage --format github.\n" \
    "The pull request's base comes from #{LOOKED} (a branch, read as origin/BRANCH;\n" \
    "KIMERA_BASE is any ref). With a base, ci mutates the changed lines, judges class-body DSL in fresh\n" \
    "mirrors and confirms survivors, as --since does. With none, ci says so and runs a full run:\n" \
    "#{UNGATED}.\n" \
    "Exit codes: 0 gates passed, 1 usage or setup error, 2 gate failed".freeze

  def initialize(io: $stdout, errors: $stderr, env: ENV, flags: Kimera::CLI::RunOptions::Usage.new)
    @io = io
    @errors = errors
    @env = env
    @flags = flags
  end

  def run(argv)
    return help if Kimera::CLI::Argv.new(argv).any?(%w[-h --help])
    arguments = (DEFAULTS + actions(argv)).reduce(argv.dup) { |given, (names, extra)| defaulted(given, names, extra) }
    Kimera::CLI::Run.new(io: @io, errors: @errors).run(arguments)
  end

  private

  def help
    @io.puts(@flags.help(BANNER))
    0
  end

  def actions(argv)
    summary = @env["GITHUB_STEP_SUMMARY"].to_s
    pairs = based(argv)
    pairs << [%w[--summary], ["--summary", summary]] unless summary.empty?
    pairs
  end

  def based(argv)
    return [] if Kimera::CLI::Argv.new(argv).any?(%w[--since])
    found = bases.map { |base| [%w[--since], ["--since", base]] }
    return found unless found.empty?
    @errors.puts("kimera ci: no pull request base found (looked for #{LOOKED}); running a full run: #{UNGATED}")
    []
  end

  def bases
    explicit = @env["KIMERA_BASE"].to_s
    return [explicit] unless explicit.empty?
    branches = BRANCHES.map { |name| @env[name].to_s }.reject { |value| value.empty? || value == "false" }
    branches.first(1).map { |branch| "origin/#{branch}" }
  end

  def defaulted(arguments, names, extra) = Kimera::CLI::Argv.new(arguments).any?(names) ? arguments : arguments + extra
end
