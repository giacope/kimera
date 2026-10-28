# frozen_string_literal: true

require_relative "null_saved"

module Kimera
  module Report
  end
end

class Kimera::Report::Actions
  ISOLATED = "mutant(s) only a fresh process can judge (validations, associations, callbacks, load-time code) " \
    "stayed unjudged and do not gate: judge them with --judge-isolated-only or `kimera run --isolated` " \
    "(on a whole Rails app that can take hours; --since judges a pull request's own)"
  OWN = { isolated: ISOLATED }.freeze
  private_constant(:OWN)

  def initialize(io: $stdout)
    @io = io
  end

  def show(report, saved = Kimera::Report::NullSaved.new)
    lines = groups(report).filter_map { |kind, found| advice(found, saved, kind) }
    @io.puts("", "Next actions:", *lines) unless lines.empty?
  end

  private

  def groups(report)
    { survivors: report.survived, unattributed: report.unattributed, uncovered: report.uncovered }
      .merge(unjudged: report.errors, isolated: report.statuses(:isolated_only))
      .merge(lapsed: report.statuses(:ignored).select(&:lapsed?))
  end

  def advice(found, saved, kind)
    first = found.min_by(&:mutant_id)
    "  #{found.size} #{OWN.fetch(kind) { saved.advice(kind, first.mutant_id) }}" if first
  end
end
