# frozen_string_literal: true

require "optparse"
require_relative "cli/flag"
require_relative "cli/help_text"
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
      Kimera::OPERATORS_FLAG,
      Kimera::CONFIG_FLAG,
      Kimera::Flag.build("--json", :json, "Print registry JSON to stdout"),
      Kimera::Flag.build(["-q", "--quiet"], :quiet, "Suppress the summary line")
    ]
  )

  COMMANDS = { "registry" => :registry, "dump" => :registry, "synthesize" => :synthesize }
    .merge("run" => :execute, "survivors" => :survivors, "report" => :report, "mutant" => :mutant)
    .merge("init" => :init, "doctor" => :doctor, "changed" => :changed, "ci" => :ci, "completion" => :completion)
    .merge("baseline" => :baseline, "skill" => :skill, "version" => :version)
    .merge("-v" => :version, "--version" => :version, "help" => :help)
    .merge("-h" => :help, "--help" => :help)
    .freeze
  private_constant(:COMMANDS)

  COMMAND_NAMES = COMMANDS.keys.grep_v(/\A-/).freeze

  def initialize(io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
  end

  def run(argv)
    dispatch(argv.dup)
  rescue Kimera::UsageError => error
    @errors.puts("kimera: #{error.message}")
    1
  end

  private

  def dispatch(argv)
    command = argv.shift || "help"
    handler = COMMANDS[command]
    return unknown(command, argv) unless handler
    __send__(handler, argv)
  end

  def unknown(command, argv)
    hint = Kimera::CLI::Suggestion.new(COMMAND_NAMES).hint(command)
    @errors.puts("kimera: unknown command #{command.inspect}#{hint}\nTry: kimera help")
    dispatch(["help", *argv])
    1
  end

  def registry(argv)
    options = Kimera::Config.scope({ output: nil, operators: Kimera::Operators::DEFAULT_KEYS, quiet: false }, argv)
    paths = REGISTRY_OPTIONS.parse(argv, options)
    files = Kimera::FileSet.scoped(paths, options)
    return missing(paths, options) if files.empty?
    build(files, options)
  end

  def missing(paths, options)
    @errors.puts("kimera: no Ruby files matched #{Kimera::FileSet.globs(paths, options).join(", ")}")
    1
  end

  def build(files, options)
    emit(scan(options).build(files), options)
  end

  def scan(options)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: options[:operators]))
  end

  def emit(built, options)
    out, json = options.values_at(:output, :json)
    built.write(out) if out
    @io.puts(built.to_json) if json
    announce(built, out) unless options[:quiet] || json
    0
  end

  def announce(built, out)
    @io.puts(built.summary)
    @io.puts("Wrote registry to #{out}") if out
  end

  def version(*)
    @io.puts("kimera #{Kimera::VERSION}")
    0
  end

  def help(*)
    @io.puts(Kimera::HelpText::HELP)
    0
  end

  def synthesize(argv) = delegate("synthesize", :Synthesize, argv)
  def execute(argv) = delegate("run", :Run, argv)
  def survivors(argv) = delegate("survivors", :Survivors, argv)
  def report(argv) = delegate("survivors", :Survivors, argv)
  def mutant(argv) = delegate("mutant", :Mutant, argv)
  def baseline(argv) = delegate("baseline", :Baseline, argv)
  def init(argv) = workflow(:Init, argv)
  def doctor(argv) = workflow(:Doctor, argv)
  def changed(argv) = workflow(:Changed, argv)
  def ci(argv) = workflow(:CI, argv)
  def completion(argv) = workflow(:Completion, argv)
  def skill(argv) = workflow(:Skill, argv)
  def workflow(name, argv) = delegate("workflows", name, argv)

  def delegate(file, name, argv)
    require_relative("cli/#{file}")
    Kimera::CLI.const_get(name).new(io: @io, errors: @errors).run(argv)
  end
end
