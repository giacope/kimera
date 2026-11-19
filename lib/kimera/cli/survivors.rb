# frozen_string_literal: true

require "optparse"
require_relative "../error"
require_relative "flag"
require_relative "outcome"
require_relative "report_file"
require_relative "../report/palette"

class Kimera::CLI::Survivors
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera report [REPORT.json] [options] [FILE_SUBSTRING]\n" \
      "Lists a report's surviving mutants; FILE_SUBSTRING keeps only " \
      "mutants whose file path contains it (e.g. models/discount).\n" \
      "REPORT.json defaults to #{Kimera::CLI::ReportFile.default}.",
    flags: [
      Kimera::Flag.build("--id ID|KEY", :id, "Show one mutant, by ID or key, in full detail"),
      Kimera::Flag.build("--report FILE", :report, "Read this report (the same as naming it first)"),
      Kimera::Flag.build("--[no-]color", :color, "Color the diffs (default: on a tty; respects NO_COLOR)"),
      Kimera::Flag.build(
        "--status NAME", :status,
        "List a different status (survived, uncovered_by_unit, no_coverage, " \
          "timeout, error, killed, isolated_only, unmutatable, unjudged: the report's harness_error)"
      )
    ]
  )

  def initialize(io: $stdout, **)
    @io = io
  end

  def run(argv)
    arguments, flags = OPTIONS.parse(argv, { status: "survived", id: nil, report: nil })
    path, filter = positional(arguments, flags[:report])
    report = load(path)
    return show(report, flags[:id], palette(flags)) if flags[:id]
    listed(report, Selection.new(flags[:status], filter, path, report.narrowed?), palette(flags))
  end

  private

  def listed(report, selection, palette)
    Kimera::CLI::Outcome::Said.new(*selection.listed(report.results, Panel.new(palette: palette)))
  end

  def palette(flags) = Kimera::Report::Palette.new(@io, flags[:color])

  def positional(arguments, named)
    first, second = arguments
    return [named, first] if named
    report?(first) ? [first, second] : [Kimera::CLI::ReportFile.default.to_s, first]
  end

  def report?(argument) = argument && (argument.end_with?(".json") || File.file?(argument))

  def load(path)
    return Kimera::CLI::ReportFile.new(path) if File.file?(path)
    raise(Kimera::UsageError, "no such report: #{path} (run kimera run first, or pass REPORT.json)")
  end

  def show(report, id, palette)
    row = report.row(id) { return Kimera::CLI::Outcome::Failed.new(1, "kimera: no mutant ##{id} in this report") }
    document = report.document
    root = document.dig("run", "source_root") || "."
    panel = Kimera::CLI::Survivors::Panel.new(tests: document.fetch("tests", {}), root: root, palette: palette)
    Kimera::CLI::Outcome::Said.new(*panel.describe(row))
  end
end

require_relative "survivors/panel"
require_relative "survivors/selection"
