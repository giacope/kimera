# frozen_string_literal: true

require_relative "../../error"
require_relative "../flag"
require_relative "../report_file"
require_relative "target"

class Kimera::CLI::Baseline::Creation
  ENTRY_KEYS = %w[file line label].freeze
  SURVIVING = %w[survived uncovered_by_unit].freeze

  CREATE = Kimera::FlagTable.new(
    banner: "Usage: kimera baseline create [REPORT.json] --reason TEXT [--output FILE] [--write]",
    flags: [
      Kimera::Flag.build("--reason TEXT", :reason, "Why this existing mutation debt is being accepted"),
      Kimera::Flag.build("--output FILE", :output, "Baseline file to write (default: .kimera-baseline.yml)"),
      Kimera::Flag.build("--write", :write, "Also set baseline: FILE in .kimera.yml"),
      Kimera::Flag.build("--force", :force, "Replace an existing baseline file")
    ]
  )

  def run(argv)
    (report,), options = CREATE.parse(
      argv, { reason: nil, output: ".kimera-baseline.yml", force: false }.merge(write: false)
    )
    report ||= Kimera::CLI::ReportFile.default.to_s
    reason = options[:reason]
    check(report, reason)
    target = Kimera::CLI::Baseline::Target.new(*options.values_at(:output, :force, :write)).checked
    target.saved(survivors(report).map { |row| entry(row, reason) })
  end

  private

  def check(report, reason)
    raise(Kimera::UsageError, "baseline create requires --reason TEXT") if reason.to_s.strip.empty?
    raise(Kimera::UsageError, "no such report: #{report}") unless File.file?(report)
  end

  def survivors(path)
    Kimera::CLI::ReportFile.new(path).results.select { |row| SURVIVING.include?(row["status"]) }
  end

  def entry(row, reason)
    id, *fields, original = row.values_at("mutant_id", *ENTRY_KEYS, "original")
    ENTRY_KEYS.zip(fields).to_h { |key, value| [key, value || missing(key, id)] }
      .merge({ "original" => original }.compact, "reason" => reason)
  end

  def missing(key, id) = raise(Kimera::UsageError, "report is missing #{key} for mutant ##{id}")
end
