# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Saved
  ADVICE = {
    survivors: ->(id, mutant, _path) { "surviving mutant(s): inspect ##{id} with `#{mutant}`" },
    uncovered: ->(_id, _mutant, path) { "uncovered mutant(s): kimera report #{path} --status no_coverage" },
    unattributed: lambda do |_id, _mutant, path|
      "mutant(s) only other units' tests reach: kimera report #{path} --status uncovered_by_unit"
    end,
    unjudged: ->(_id, mutant, _path) { "unjudged mutant(s): see why with `#{mutant}`" },
    lapsed: lambda do |_id, _mutant, path|
      "ignored mutant(s) now killed: `kimera baseline prune BASELINE.yml --report #{path}`"
    end
  }.freeze
  private_constant(:ADVICE)

  def initialize(path)
    @path = path
  end

  def advice(kind, id) = ADVICE.fetch(kind).call(id, mutant(id), @path)

  def more(id) = "; all of them: #{mutant(id)}"

  def listing = "list them with: kimera report #{@path} --status no_coverage"

  private

  def mutant(id) = "kimera mutant #{id} --report #{@path}"
end
