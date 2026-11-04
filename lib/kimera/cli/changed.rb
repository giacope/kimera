# frozen_string_literal: true

require_relative "../error"
require_relative "argv"
require_relative "run"

class Kimera::CLI::Changed
  def initialize(io: $stdout, errors: $stderr, run: Kimera::CLI::Run.new(io: io, errors: errors))
    @run = run
  end

  def run(argv)
    arguments = argv.dup
    arguments.unshift("--since", reference) unless Kimera::CLI::Argv.new(arguments).option?("--since")
    @run.run(arguments)
  end

  private

  def reference
    %w[origin/main main].find { |name| branch?(name) } ||
      raise(Kimera::UsageError, "cannot find origin/main or main; pass --since REF")
  end

  def branch?(name) = system("git", "rev-parse", "--verify", "--quiet", name, out: File::NULL, err: File::NULL)
end
