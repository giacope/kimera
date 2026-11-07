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
  GROUPS = {
    survivors: :survived, unattributed: :uncovered_by_unit, uncovered: :no_coverage, unjudged: :harness_error,
    isolated: :isolated_only
  }.freeze
  private_constant(:OWN, :GROUPS)

  def initialize(io: $stdout)
    @io = io
  end

  def show(report, saved = Kimera::Report::NullSaved.new)
    lines = groups(report).flat_map { |kind, found| advice(found, saved, kind) }
    @io.puts("", "Next actions:", *lines) unless lines.empty?
  end

  private

  def groups(report)
    GROUPS.transform_values { |status| report.select { |result| result.status?(status) } }
      .merge(lapsed: report.select { |result| result.status?(:ignored) && result.lapsed? })
  end

  def advice(found, saved, kind)
    found.min(1).map do |first|
      "  #{found.size} #{OWN.fetch(kind) { saved.advice(kind, first.to_h["mutant_id"]) }}"
    end
  end
end
