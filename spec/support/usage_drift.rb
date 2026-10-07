# frozen_string_literal: true

require "kimera/cli"
require "kimera/cli/baseline"
require "kimera/cli/mutant"
require "kimera/cli/run"
require "kimera/cli/survivors"
require "kimera/cli/synthesize"
require "kimera/cli/workflows"
require "kimera/scope/ignore_list"

# Checks what a document tells people to type against the CLI as built: each
# `kimera <command>` exists, each flag on it is one that command parses, every
# flag mentioned anywhere is one some command parses, each top-level key of a
# YAML block that configures Kimera (and, with spans: true, each `key: value`
# code span) is one .kimera.yml or an ignore entry reads, and each --operators
# value is an operator or group.
class UsageDrift
  RUN = Kimera::CLI::RunOptions::OPTIONS
  REPORT = Kimera::CLI::Survivors::OPTIONS
  REGISTRY = Kimera::CLI::REGISTRY_OPTIONS
  TABLES = {
    "run" => RUN, "changed" => RUN, "ci" => RUN, "mutant" => Kimera::CLI::Mutant::OPTIONS,
    "report" => REPORT, "survivors" => REPORT, "registry" => REGISTRY, "dump" => REGISTRY,
    "init" => Kimera::CLI::Init::OPTIONS, "doctor" => Kimera::CLI::Doctor::OPTIONS,
    "synthesize" => Kimera::CLI::Synthesize::OPTIONS, "baseline" => nil,
    "baseline create" => Kimera::CLI::Baseline::Creation::CREATE,
    "baseline review" => Kimera::CLI::Baseline::REVIEW, "baseline prune" => Kimera::CLI::Baseline::PRUNE,
    "completion" => nil, "skill" => nil, "version" => nil, "help" => nil
  }.freeze
  CONFIG = (Kimera::Config::SCALAR_KEYS + Kimera::Config::LIST_KEYS).freeze
  KEYS = (CONFIG + Kimera::IgnoreList::ANCHORS.keys.map(&:to_s) + %w[ignore file reason format_version]).freeze
  INVOCATION = /\bkimera\s+(?<command>[a-z]+)(?<rest>[^`]*)/
  FLAG = /(?<![\w-])--[a-z][a-z0-9-]*/
  SETTING = /\A(?<key>[a-z][a-z0-9_]*):(?: .*)?\z/
  TOP_KEY = /^(?<key>[a-z][a-z0-9_]*):/

  def initialize(text, spans: true)
    @text = text
    @spans = spans
  end

  def problems = (unknown + misplaced + flags + keys + operators).uniq

  def commands = calls.map(&:first).uniq

  private

  def code = fenced + inline

  def fenced
    @text.scan(/^```[^\n]*\n(.*?)^```/m).flatten.flat_map { |block| block.lines.map { |line| line.sub(/\s#\s.*/, "") } }
  end

  def inline = @text.gsub(/^```.*?^```/m, "").scan(/`([^`]+)`/).flatten.map { |span| span.split.join(" ") }

  def calls = code.flat_map { |fragment| fragment.scan(INVOCATION).map { |command, rest| call(command, rest) } }

  def call(command, rest)
    sub = rest[/\A\s*(create|review|prune)\b/, 1] if command == "baseline"
    sub ? ["baseline #{sub}", rest.sub(/\A\s*[a-z]+/, "")] : [command, rest]
  end

  def unknown = (commands - TABLES.keys).map { |command| "unknown command: kimera #{command}" }

  def misplaced
    calls.select { |command,| TABLES.key?(command) }.flat_map do |command, rest|
      stray = rest.scan(FLAG).reject { |flag| accepts?(TABLES[command], flag) }
      stray.map { |flag| "kimera #{command} has no #{flag}" }
    end
  end

  def flags
    known = TABLES.values.compact.uniq.flat_map { |table| switches(table) }
    (@text.scan(FLAG).uniq - known - ["--help"]).map { |flag| "no command has #{flag}" }
  end

  def keys = ((spans + configs).uniq - KEYS).map { |key| "no config key or ignore anchor: #{key}:" }

  # `kimera: <phase> ...` is the progress prefix, not a setting.
  def spans = @spans ? code.filter_map { |fragment| fragment.strip[SETTING, :key] } - ["kimera"] : []

  # jobs: is also a GitHub workflow key, so it does not mark a block as Kimera's.
  def configs
    blocks = @text.scan(/^```ya?ml\n(.*?)^```/m).flatten.map { |block| block.scan(TOP_KEY).flatten }
    blocks.select { |found| found.intersect?(CONFIG - ["jobs"]) }.flatten
  end

  def operators
    named = @text.scan(/--operators[ =]([a-z_,]+)/).flatten.flat_map { |list| list.split(",") }.uniq
    named.reject { |key| (Kimera::Operators.expand([key]) - Kimera::Operators.keys).empty? }
      .map { |key| "unknown operator: #{key}" }
  end

  def accepts?(table, flag) = flag == "--help" || (table && switches(table).include?(flag))

  def switches(table)
    table.flags.flat_map { |flag| Array(flag.switch) }.map { |switch| switch.split.first }.flat_map do |switch|
      negatable = switch.match(/\A--\[no-\](?<name>.+)\z/)
      negatable ? ["--#{negatable[:name]}", "--no-#{negatable[:name]}"] : [switch]
    end
  end
end
