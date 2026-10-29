# frozen_string_literal: true

require "optparse"
require_relative "cli/flag"
require_relative "cli/handlers"
require_relative "cli/help_text"
require_relative "cli/interruption"
require_relative "cli/outcome"
require_relative "cli/suggestion"
require_relative "operators"
require_relative "registry/builder"
require_relative "scope/config"
require_relative "scope/file_set"
require_relative "version"

class Kimera::CLI
  REGISTRY_OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera registry [paths...] [options]",
    flags: [
      Kimera::Flag.build(["-o", "--output FILE"], :output, "Write registry JSON to FILE"),
      Kimera::Flag.shared(:operators),
      Kimera::Flag.shared(:config),
      Kimera::Flag.build("--json", :json, "Print registry JSON to stdout"),
      Kimera::Flag.build(["-q", "--quiet"], :quiet, "Suppress the summary line")
    ]
  )

  COMMANDS = { "registry" => :registry, "dump" => :registry, "synthesize" => :synthesize }
    .merge("run" => :execute, "survivors" => :survivors, "report" => :report, "mutant" => :mutant)
    .merge("init" => :configure, "doctor" => :doctor, "changed" => :changed, "ci" => :ci, "completion" => :completion)
    .merge("baseline" => :baseline, "skill" => :skill, "version" => :version)
    .merge("-v" => :version, "--version" => :version, "help" => :help)
    .merge("-h" => :help, "--help" => :help)
    .freeze
  private_constant(:COMMANDS)

  ALIASES = %w[dump survivors].freeze
  COMMAND_NAMES = (COMMANDS.keys.grep_v(/\A-/) - ALIASES).freeze

  def initialize(io: $stdout, errors: $stderr, handlers: Kimera::CLI::Handlers.new(io, errors))
    @handlers = handlers
  end

  def run(argv)
    @handlers.guard(Process.pid).guard { dispatch(argv.dup) }
  rescue Kimera::UsageError => error
    refused("kimera: #{error.message}")
  end

  private

  def dispatch(argv)
    command, *rest = argv
    handler = COMMANDS[command || "help"]
    return unknown(command, rest) unless handler
    __send__(handler, rest)
  end

  def unknown(command, _argv)
    hint = Kimera::CLI::Suggestion.new(COMMAND_NAMES).hint(command)
    refused("kimera: unknown command #{command.inspect}#{hint}\nTry: kimera help")
  end

  def registry(argv)
    defaults = { output: nil, operators: Kimera::Operators.build.map(&:key), quiet: false }
    paths, options = REGISTRY_OPTIONS.parse(argv, Kimera::Config.parse(argv).scope(defaults))
    set = Kimera::FileSet.from_options(paths, options)
    files = set.files
    return missing(set) if files.empty?
    build(files, options)
  end

  def missing(set) = refused("kimera: no Ruby files matched #{set}")

  def refused(text) = Kimera::CLI::Outcome::Failed.new(1, text)

  def build(files, options)
    built = scan(options).build(files)
    out = options[:output]
    built.write(out) if out
    emit(built, options)
  end

  def scan(options)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: options[:operators]))
  end

  def emit(built, options)
    out, json = options.values_at(:output, :json)
    return Kimera::CLI::Outcome::Said.new(built.to_json) if json
    options[:quiet] ? Kimera::CLI::Outcome::Ended.new(0) : Kimera::CLI::Outcome::Said.new(*announced(built, out))
  end

  def announced(built, out) = [built.summary, *(out ? ["Wrote registry to #{out}"] : [])]

  def version(*) = Kimera::CLI::Outcome::Said.new("kimera #{Kimera::VERSION}")

  def help(*) = @handlers.help

  def synthesize(argv) = delegate("synthesize", :Synthesize, argv)
  def execute(argv) = delegate("run", :Run, argv)
  def survivors(argv) = delegate("survivors", :Survivors, argv)
  def report(argv) = delegate("survivors", :Survivors, argv)
  def mutant(argv) = delegate("mutant", :Mutant, argv)
  def baseline(argv) = delegate("baseline", :Baseline, argv)
  def configure(argv) = workflow(:Init, argv)
  def doctor(argv) = workflow(:Doctor, argv)
  def changed(argv) = workflow(:Changed, argv)
  def ci(argv) = workflow(:CI, argv)
  def completion(argv) = workflow(:Completion, argv)
  def skill(argv) = workflow(:Skill, argv)
  def workflow(name, argv) = delegate("workflows", name, argv)

  def delegate(file, name, argv) = @handlers.run(file, name, argv)
end
