# frozen_string_literal: true

require "yaml"
require_relative "../error"
require_relative "flag"
require_relative "report_file"

class Kimera::CLI::Baseline
  COMMANDS = { "create" => :create, "review" => :review, "prune" => :prune }.freeze
  ENTRY_KEYS = %w[file line label].freeze
  REPORT_FLAG = Kimera::Flag.build("--report FILE", :report, "Judge each entry against this report")

  CREATE = Kimera::FlagTable.new(
    banner: "Usage: kimera baseline create REPORT.json --reason TEXT [--output FILE]",
    flags: [
      Kimera::Flag.build("--reason TEXT", :reason, "Why this existing mutation debt is being accepted"),
      Kimera::Flag.build("--output FILE", :output, "Baseline file to write (default: .kimera-baseline.yml)"),
      Kimera::FORCE_FLAG.with(help: "Replace an existing baseline file")
    ]
  )

  REVIEW = Kimera::FlagTable.new(
    banner: "Usage: kimera baseline review BASELINE.yml [--report REPORT.json]",
    flags: [REPORT_FLAG]
  )

  PRUNE = Kimera::FlagTable.new(
    banner: "Usage: kimera baseline prune BASELINE.yml --report REPORT.json [--dry-run]",
    flags: [REPORT_FLAG, Kimera::Flag.build("--dry-run", :dry_run, "Print what would change; leave the file as is")]
  )

  def initialize(io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
  end

  def run(argv)
    __send__(command(argv.shift), argv)
  rescue Kimera::UsageError => error
    @errors.puts("kimera: #{error.message}")
    1
  end

  private

  def command(name)
    COMMANDS.fetch(name) { raise(Kimera::UsageError, "usage: kimera baseline <create|review|prune> ...") }
  end

  def create(argv)
    options = { reason: nil, output: ".kimera-baseline.yml", force: false }
    report, = CREATE.parse(argv, options)
    check(report, options)
    write(report, options[:output], options[:reason])
  end

  def check(report, options)
    raise(Kimera::UsageError, "baseline create needs a report file") unless report
    raise(Kimera::UsageError, "baseline create requires --reason TEXT") if options[:reason].to_s.strip.empty?
    raise(Kimera::UsageError, "no such report: #{report}") unless File.file?(report)
    output = options[:output]
    overwrite(output) if File.exist?(output) && !options[:force]
  end

  def overwrite(output) = raise(Kimera::UsageError, "#{output} already exists (use --force to replace it)")

  def write(report, output, reason)
    ignored = survivors(report).map { |row| entry(row, reason) }
    File.write(output, YAML.dump("format_version" => 1, "ignore" => ignored))
    @io.puts("Created #{output} with #{ignored.size} accepted survivor(s).")
    @io.puts("Add `baseline: #{output}` to .kimera.yml to apply it.")
    0
  end

  def review(argv)
    options = { report: nil }
    file = baseline(REVIEW, argv, options)
    report = options[:report]
    report ? Review.new(io: @io).show(ledger(file, report)) : list(file)
  end

  def prune(argv)
    options = { dry_run: false }
    file = baseline(PRUNE, argv, options)
    report = options.fetch(:report) { raise(Kimera::UsageError, "baseline prune needs --report FILE") }
    pruning = Prune.new(ledger(file, report), io: @io)
    options[:dry_run] ? pruning.preview : pruning.apply
  end

  def baseline(table, argv, options)
    file, *rest = table.parse(argv, options)
    raise(Kimera::UsageError, table.banner) unless file && rest.empty?
    existing(file)
  end

  def existing(file) = File.file?(file) ? file : raise(Kimera::UsageError, "no such baseline: #{file}")

  def ledger(file, report)
    raise(Kimera::UsageError, "no such report: #{report}") unless File.file?(report)
    Ledger.new(file, report)
  end

  def list(file)
    entries = Array((YAML.safe_load_file(file) || {})["ignore"])
    @io.puts("#{entries.size} accepted mutant(s) in #{file}:")
    entries.sort_by { |entry| [entry["file"], entry["line"], entry["label"]] }.each { |entry| @io.puts(line(entry)) }
    0
  end

  def line(entry) = "  #{entry["file"]}:#{entry["line"]} [#{entry["label"]}] — #{entry["reason"]}"

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

require_relative "baseline/ledger"
require_relative "baseline/prune"
require_relative "baseline/review"
