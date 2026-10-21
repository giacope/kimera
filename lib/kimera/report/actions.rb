# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Actions
  ISOLATED = "mutant(s) only a fresh process can judge (validations, associations, callbacks, load-time code) " \
    "stayed unjudged and do not gate: judge them with --judge-isolated-only or `kimera run --isolated` " \
    "(on a whole Rails app that can take hours; --since judges a pull request's own)"
  def initialize(io: $stdout)
    @io = io
  end

  def show(report, path: nil)
    hints = path ? SavedHints.new(path) : UnsavedHints.new
    lines = groups(report).filter_map { |kind, found| advice(found, hints, kind) }
    @io.puts("", "Next actions:", *lines) unless lines.empty?
  end

  private

  def groups(report)
    { survivors: report.survived, unattributed: report.unattributed, uncovered: report.uncovered }
      .merge(unjudged: report.errors, isolated: report.statuses(:isolated_only))
      .merge(lapsed: report.statuses(:ignored).select(&:lapsed?))
  end

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

    def unattributed(_id) = "mutant(s) only other units' tests reach: kimera report #{@path} --status uncovered_by_unit"

    def unjudged(id) = "unjudged mutant(s): see why with `#{mutant(id)}`"

    def isolated(_id) = ISOLATED

    def lapsed(_id) = "ignored mutant(s) now killed: `kimera baseline prune BASELINE.yml --report #{@path}`"

    private

    def mutant(id) = "kimera mutant #{id} --report #{@path}"
  end

  class UnsavedHints
    def survivors(id) = "surviving mutant(s): run without --no-report to save one, then `kimera mutant #{id}`"

    def uncovered(_id) = "uncovered mutant(s): run without --no-report, then `kimera report --status no_coverage`"

    def unattributed(_id) = "mutant(s) only other units' tests reach: write a unit test that runs each"

    def unjudged(_id) = "unjudged mutant(s): retry with `kimera run --isolated`"

    def isolated(_id) = ISOLATED

    def lapsed(_id) = "ignored mutant(s) now killed: run without --no-report, then `kimera baseline prune`"
  end
end
