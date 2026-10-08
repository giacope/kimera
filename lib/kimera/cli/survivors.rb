# frozen_string_literal: true

require "optparse"
require_relative "../error"
require_relative "flag"
require_relative "report_file"

class Kimera::CLI::Survivors
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera report [REPORT.json] [options] [FILE_SUBSTRING]\n" \
      "Lists a report's surviving mutants; FILE_SUBSTRING keeps only " \
      "mutants whose file path contains it (e.g. models/discount).\n" \
      "REPORT.json defaults to #{Kimera::CLI::ReportFile::DEFAULT}.",
    flags: [
      Kimera::Flag.build("--id ID|KEY", :id, "Show one mutant, by ID or key, in full detail"),
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
    document = load(options[:report])
    results = document.fetch("results", [])
    id = options[:id]
    id ? show(results, id, document) : list(results, options)
  end

  def parse(argv)
    options = { status: "survived", id: nil }
    report, filter = positional(OPTIONS.parse(argv, options))
    options.merge(report: report, filter: filter)
  end

  def positional(args)
    first, second = args
    report?(first) ? [first, second] : [Kimera::CLI::ReportFile::DEFAULT, first]
  end

  def report?(arg) = arg && (arg.end_with?(".json") || File.file?(arg))

  def load(path)
    return Kimera::CLI::ReportFile.parse(path) if File.file?(path)
    raise(Kimera::UsageError, "no such report: #{path} (run kimera run first, or pass REPORT.json)")
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

  def show(results, id, document)
    row = Kimera::CLI::ReportFile.row(results, id)
    return missing(id) unless row
    root = document.dig("run", "source_root") || "."
    Panel.new(io: @io, tests: document.fetch("tests", {}), root: root).describe(row)
    0
  end

  def missing(id)
    @errors.puts("kimera: no mutant ##{id} in this report")
    1
  end
end

require_relative "survivors/panel"
