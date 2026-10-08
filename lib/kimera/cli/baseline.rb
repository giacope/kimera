# frozen_string_literal: true

require "yaml"
require_relative "../error"
require_relative "flag"
require_relative "report_file"

class Kimera::CLI::Baseline
  COMMANDS = { "create" => :create, "review" => :review, "prune" => :prune }
    .merge("help" => :help, "--help" => :help, "-h" => :help).freeze
  HELP = <<~HELP.freeze
    Usage: kimera baseline <command> [options]

      create [REPORT.json] --reason TEXT [--write]  Accept a report's survivors as reviewed debt
      review BASELINE.yml [--report REPORT.json]    List the entries, or judge them against a report
      prune BASELINE.yml --report REPORT.json       Drop the entries a report shows killed or stale

    REPORT.json defaults to #{Kimera::CLI::ReportFile::DEFAULT}. Run kimera baseline <command> --help for its options.
  HELP
  REPORT_FLAG = Kimera::Flag.build("--report FILE", :report, "Judge each entry against this report")

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
    COMMANDS.fetch(name) do
      raise(Kimera::UsageError, "#{name ? "unknown baseline command #{name.inspect}" : "missing command"}\n#{HELP}")
    end
  end

  def help(_argv)
    @io.write(HELP)
    0
  end

  def create(argv) = Kimera::CLI::Baseline::Creation.new(io: @io).run(argv)

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
end

require_relative "baseline/creation"
require_relative "baseline/ledger"
require_relative "baseline/setting"
require_relative "baseline/prune"
require_relative "baseline/review"
