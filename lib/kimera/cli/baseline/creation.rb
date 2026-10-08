# frozen_string_literal: true

require "yaml"
require_relative "../../error"
require_relative "../../scope/config"
require_relative "../flag"
require_relative "../report_file"

class Kimera::CLI::Baseline::Creation
  ENTRY_KEYS = %w[file line label].freeze

  CREATE = Kimera::FlagTable.new(
    banner: "Usage: kimera baseline create [REPORT.json] --reason TEXT [--output FILE] [--write]",
    flags: [
      Kimera::Flag.build("--reason TEXT", :reason, "Why this existing mutation debt is being accepted"),
      Kimera::Flag.build("--output FILE", :output, "Baseline file to write (default: .kimera-baseline.yml)"),
      Kimera::Flag.build("--write", :write, "Also set baseline: FILE in .kimera.yml"),
      Kimera::FORCE_FLAG.with(help: "Replace an existing baseline file")
    ]
  )

  def initialize(io: $stdout)
    @io = io
  end

  def run(argv)
    options = { reason: nil, output: ".kimera-baseline.yml", force: false }.merge(write: false)
    report, = CREATE.parse(argv, options)
    report ||= Kimera::CLI::ReportFile::DEFAULT
    check(report, options)
    write(report, options)
  end

  private

  def check(report, options)
    raise(Kimera::UsageError, "baseline create requires --reason TEXT") if options[:reason].to_s.strip.empty?
    raise(Kimera::UsageError, "no such report: #{report}") unless File.file?(report)
    output = options[:output]
    overwrite(output) if File.exist?(output) && !options[:force]
  end

  def overwrite(output) = raise(Kimera::UsageError, "#{output} already exists (use --force to replace it)")

  def write(report, options)
    output = options[:output]
    ignored = survivors(report).map { |row| entry(row, options[:reason]) }
    File.write(output, YAML.dump("format_version" => 1, "ignore" => ignored))
    @io.puts("Created #{output} with #{ignored.size} accepted survivor(s).", applied(output, options))
    0
  end

  def applied(output, options) = options[:write] ? set(output) : hint(output)

  def hint(output) = "Add `baseline: #{output}` to .kimera.yml to apply it, or rerun with --write."

  def set(output)
    Kimera::CLI::Baseline::Setting.new(Kimera::Config::DEFAULT_PATH).apply(output)
    "Set `baseline: #{output}` in #{Kimera::Config::DEFAULT_PATH}."
  end

  def survivors(path)
    Kimera::CLI::ReportFile.parse(path).fetch("results", []).select { |row| row["status"] == "survived" }
  end

  def entry(row, reason)
    id, *fields, original = row.values_at("mutant_id", *ENTRY_KEYS, "original")
    ENTRY_KEYS.zip(fields).to_h { |key, value| [key, value || missing(key, id)] }
      .merge({ "original" => original }.compact, "reason" => reason)
  end

  def missing(key, id) = raise(Kimera::UsageError, "report is missing #{key} for mutant ##{id}")
end
