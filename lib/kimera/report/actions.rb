# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Actions
  def initialize(io: $stdout)
    @io = io
  end

  def show(report, path: nil)
    hints = path ? SavedHints.new(path) : UnsavedHints.new
    lines = [
      advice(report.survived, hints, :survivors), advice(report.uncovered, hints, :uncovered),
      advice(report.errors, hints, :unjudged), advice(report.statuses(:ignored).select(&:lapsed?), hints, :lapsed)
    ].compact
    @io.puts("", "Next actions:", *lines) unless lines.empty?
  end

  private

  def advice(found, hints, kind)
    first = found.min_by(&:mutant_id)
    "  #{found.size} #{hints.public_send(kind, first.mutant_id)}" if first
  end

  class SavedHints
    def initialize(path)
      @path = path
    end

    def survivors(id) = "surviving mutant(s): inspect ##{id} with `#{mutant(id)}`"

    def uncovered(_id) = "uncovered mutant(s): kimera report #{@path} --status no_coverage"

    def unjudged(id) = "unjudged mutant(s): see why with `#{mutant(id)}`"

    def lapsed(_id) = "ignored mutant(s) now killed: `kimera baseline prune BASELINE.yml --report #{@path}`"

    private

    def mutant(id) = "kimera mutant #{id} --report #{@path}"
  end

  class UnsavedHints
    def survivors(id) = "surviving mutant(s): run without --no-report to save one, then `kimera mutant #{id}`"

    def uncovered(_id) = "uncovered mutant(s): run without --no-report, then `kimera report --status no_coverage`"

    def unjudged(_id) = "unjudged mutant(s): retry with `kimera run --isolated`"

    def lapsed(_id) = "ignored mutant(s) now killed: run without --no-report, then `kimera baseline prune`"
  end
end
