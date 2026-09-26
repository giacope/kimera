# frozen_string_literal: true

require_relative "../error"
require_relative "argv"
require_relative "run"

class Kimera::CLI::Changed
  def initialize(io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
  end

  def run(argv)
    args = argv.dup
    args.unshift("--since", reference) unless Kimera::CLI::Argv.option?(args, "--since")
    Kimera::CLI::Run.new(io: @io, errors: @errors).run(args)
  end

  private

  def reference
    %w[origin/main main].find { |name| branch?(name) } ||
      raise(Kimera::UsageError, "cannot find origin/main or main; pass --since REF")
  end

  def branch?(name) = system("git", "rev-parse", "--verify", "--quiet", name, out: File::NULL, err: File::NULL)
end
