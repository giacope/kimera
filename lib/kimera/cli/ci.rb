# frozen_string_literal: true

require_relative "argv"
require_relative "run"

class Kimera::CLI::CI
  DEFAULTS = [
    [%w[--max-survivors], %w[--max-survivors 0]],
    [%w[--fail-on-no-coverage --no-fail-on-no-coverage], %w[--fail-on-no-coverage]],
    [%w[--format], %w[--format github]]
  ].freeze

  def initialize(io: $stdout, errors: $stderr, env: ENV)
    @io = io
    @errors = errors
    @env = env
  end

  def run(argv)
    arguments = (DEFAULTS + actions).reduce(argv.dup) { |given, (names, extra)| defaulted(given, names, extra) }
    Kimera::CLI::Run.new(io: @io, errors: @errors).run(arguments)
  end

  private

  def actions
    base, summary = @env.values_at("GITHUB_BASE_REF", "GITHUB_STEP_SUMMARY").map(&:to_s)
    pairs = []
    pairs << [%w[--since], ["--since", "origin/#{base}"]] unless base.empty?
    pairs << [%w[--summary], ["--summary", summary]] unless summary.empty?
    pairs
  end

  def defaulted(arguments, names, extra) = Kimera::CLI::Argv.any?(arguments, names) ? arguments : arguments + extra
end
