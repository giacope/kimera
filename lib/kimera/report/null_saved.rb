# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::NullSaved
  ADVICE = {
    survivors: ->(id) { "surviving mutant(s): run without --no-report to save one, then `kimera mutant #{id}`" },
    uncovered: ->(_id) { "uncovered mutant(s): run without --no-report, then `kimera report --status no_coverage`" },
    unattributed: ->(_id) { "mutant(s) only other units' tests reach: write a unit test that runs each" },
    unjudged: ->(_id) { "unjudged mutant(s): retry with `kimera run --isolated`" },
    lapsed: ->(_id) { "ignored mutant(s) now killed: run without --no-report, then `kimera baseline prune`" }
  }.freeze
  private_constant(:ADVICE)

  def advice(kind, id) = ADVICE.fetch(kind).call(id)

  def more(_id) = ""

  def listing = "run without --no-report, then `kimera report --status no_coverage` to list them"
end
