# frozen_string_literal: true

require "optparse"
require_relative "../operators"
require_relative "../registry/builder"
require_relative "../scope/config"
require_relative "../scope/file_set"
require_relative "../synthesis/project"
require_relative "flag"

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Synthesize
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera synthesize [paths...] [options]",
    flags: [
      Kimera::Flag.build("--out DIR", :out, "Write synthesized mirror tree to DIR"),
      Kimera::REGISTRY_FLAG,
      Kimera::OPERATORS_FLAG,
      Kimera::CONFIG_FLAG
    ]
  )

  def initialize(io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
  end

  def run(argv)
    options = Kimera::Config.scope({ out: nil, registry: nil, operators: Kimera::Operators::DEFAULT_KEYS }, argv)
    paths = OPTIONS.parse(argv, options)
    out = options[:out]
    out ? synthesize(paths, options, out) : missing
  end

  private

  def missing
    @errors.puts("kimera synthesize: --out DIR is required")
    1
  end

  def synthesize(paths, options, out)
    registry = load(paths, options)
    report(registry, Kimera::Synthesis::Project.new(registry).write(out), out)
    0
  end

  def report(registry, manifest, out)
    @io.puts("Synthesized #{registry.files.size} files to #{out}.")
    @io.puts("  #{manifest.mutant_files.size} mutants on the schema path.")
    unsafe = manifest.unsafe_mutants
    @io.puts("  #{unsafe.size} mutants routed to reload fallback (memoization).") unless unsafe.empty?
  end

  def load(paths, options)
    stored = options[:registry]
    return Kimera::Registry.load(stored) if stored
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: options[:operators]))
      .build(Kimera::FileSet.scoped(paths, options))
  end
end
