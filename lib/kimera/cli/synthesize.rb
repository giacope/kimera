# frozen_string_literal: true

require "optparse"
require_relative "../operators"
require_relative "../registry/builder"
require_relative "../scope/config"
require_relative "../scope/file_set"
require_relative "../synthesis/project"
require_relative "flag"
require_relative "outcome"

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Synthesize
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera synthesize [paths...] [options]",
    flags: [
      Kimera::Flag.build("--out DIR", :out, "Write synthesized mirror tree to DIR"),
      Kimera::Flag.shared(:registry),
      Kimera::Flag.shared(:operators),
      Kimera::Flag.shared(:config)
    ]
  )

  MISSING = "kimera synthesize: --out DIR is required"

  def initialize(**); end

  def run(argv)
    operators = Kimera::Operators.build.map(&:key)
    defaults = Kimera::Config.parse(argv).scope({ out: nil, registry: nil, operators: operators })
    paths, options = OPTIONS.parse(argv, defaults)
    out = options[:out]
    out ? synthesize(paths, options, out) : missing
  end

  private

  def missing = Kimera::CLI::Outcome::Failed.new(1, MISSING)

  def synthesize(paths, options, out)
    registry = load(paths, options)
    manifest = Kimera::Synthesis::Project.new(registry).write(out)
    Kimera::CLI::Outcome::Said.new(*report(registry, manifest, out))
  end

  def report(registry, manifest, out)
    unsafe = manifest.unsafe_mutants
    routed = unsafe.empty? ? [] : ["  #{unsafe.size} mutants routed to reload fallback (memoization)."]
    schema = "  #{manifest.mutant_files.size} mutants on the schema path."
    ["Synthesized #{registry.files.size} files to #{out}.", schema, *routed]
  end

  def load(paths, options)
    stored = options[:registry]
    return Kimera::Registry.from_file(stored) if stored
    operators = Kimera::Operators.build(keys: options[:operators])
    files = Kimera::FileSet.from_options(paths, options).files
    Kimera::RegistryScan.new(operators: operators).build(files)
  end
end
