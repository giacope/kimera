# frozen_string_literal: true

require "optparse"
require_relative "../error"
require_relative "flag"
require_relative "report_file"

class Kimera::CLI::Survivors
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera survivors REPORT.json [options] [FILE_SUBSTRING]\n" \
      "Lists a report's surviving mutants; FILE_SUBSTRING keeps only " \
      "mutants whose file path contains it (e.g. models/discount).",
    flags: [
      Kimera::Flag.build("--id N", :id, "Show one mutant in full detail", type: Integer),
      Kimera::Flag.build(
        "--status NAME", :status,
        "List a different status (survived, no_coverage, " \
          "timeout, error, killed, isolated_only, unmutatable)"
      )
    ]
  )

  def initialize(io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
  end

  def run(argv)
    attempt(argv)
  rescue Kimera::UsageError => error
    @errors.puts("kimera: #{error.message}")
    1
  end

  private

  def attempt(argv)
    options = parse(argv)
    results = load(options[:report]).fetch("results", [])
    id = options[:id]
    id ? show(results, id) : list(results, options)
  end

  def parse(argv)
    options = { status: "survived", id: nil }
    report, filter = OPTIONS.parse(argv, options)
    raise(Kimera::UsageError, "survivors: a report file is required (run with --report FILE first)") unless report
    options.merge(report: report, filter: filter)
  end

  def load(path)
    raise(Kimera::UsageError, "no such report: #{path}") unless File.file?(path)
    Kimera::CLI::ReportFile.parse(path)
  end

  def list(results, options)
    matching = matches(results, options)
    return none(options) if matching.empty?
    Panel.new(io: @io).announce(matching, options)
    0
  end

  def matches(results, options)
    status = options[:status]
    filter = options[:filter]
    found = results.select { |row| row["status"] == status }.map { |row| [row["file"].to_s, row["line"] || 0, row] }
    filter ? found.select { |file,| file.include?(filter) } : found
  end

  def none(options)
    filter = options[:filter]
    @io.puts("no #{options[:status]} mutants#{" matching #{filter}" if filter}")
    0
  end

  def show(results, id)
    row = results.find { |candidate| candidate["mutant_id"] == id }
    return missing(id) unless row
    Panel.new(io: @io).describe(row)
    0
  end

  def missing(id)
    @errors.puts("kimera: no mutant ##{id} in this report")
    1
  end
end

require_relative "survivors/panel"
