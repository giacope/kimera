# frozen_string_literal: true

require_relative "actions"
require_relative "entries"
require_relative "file_table"
require_relative "null_saved"
require_relative "palette"
require_relative "remarks"
require_relative "saved"
require_relative "test_health"
require_relative "test_list"

module Kimera
  module Report
  end
end

class Kimera::Report::Text
  def initialize(registry, io: $stdout, color: nil, palette: Kimera::Report::Palette.new(io, color))
    @registry = registry
    @io = io
    @palette = palette
  end

  COVERAGE_SECTIONS = { hint: :hint, list: :missing }.freeze

  def report(report, scope: [], coverage: :hint) = written(report, scope, coverage, Kimera::Report::NullSaved.new)

  def saved(report, path, scope: [], coverage: :hint)
    written(report, scope, coverage, Kimera::Report::Saved.new(path))
  end

  private

  def written(report, scope, coverage, saved)
    header(report, scope)
    survivors(report, Kimera::Report::TestList.new(report, saved))
    footer(report, coverage, saved, narrowed: !scope.empty?)
  end

  def header(report, scope)
    scope.each { |line| @io.puts(line) }
    @io.puts(@palette.bold(report.summary))
    Kimera::Report::FileTable.new(io: @io).show(report)
  end

  def footer(report, coverage, saved, narrowed:)
    entries.public_send(COVERAGE_SECTIONS.fetch(coverage), report, saved, narrowed: narrowed)
    report.regions { |found| remarks.regions(found) }
    remarks.leaks(report.leaks)
    health.flaky(report)
    health.quality(report)
    Kimera::Report::Actions.new(io: @io).show(report, saved)
  end

  def survivors(report, tests)
    entries.survived(report, tests)
    entries.unjudged(report)
    remarks.waivers(report)
    remarks.rejudged(report)
  end

  def entries = Kimera::Report::Entries.new(@io, @registry, @palette)

  def remarks = Kimera::Report::Remarks.new(@io, @palette)

  def health = Kimera::Report::TestHealth.new(@io, @palette)
end
