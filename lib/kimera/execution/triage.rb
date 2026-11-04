# frozen_string_literal: true

require_relative "../self_protection"
require_relative "verdicts"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Triage
  SELF_SUSPECT = %i[timeout error survived].freeze

  def initialize(verdicts)
    @verdicts = verdicts
  end

  def tiers(ids)
    safe, unsafe = ids.partition { |id| @verdicts.point(id).safe? }
    [safe, *unsafe.partition { |id| @verdicts.point(id).reasons(Kimera::Reason.unreloadable).empty? }]
  end

  def quarantine(id)
    found = @verdicts.point(id)
    Kimera::MutantResult.new(mutant_id: id, status: held(found), file: found.file, detail: found.reasons(Kimera::Reason.unsafety).first)
  end

  def reclassified(results) = results.transform_values { |result| reclassify(result) }

  private

  def held(point)
    return :unmutatable if point.reasons(Kimera::Reason.unmutatable).any?
    point.reasons(Kimera::Reason.unloaded).any? ? :no_coverage : :isolated_only
  end

  def reclassify(result) = suspect?(result) ? result.isolated(detail(result.status)) : result

  def suspect?(result)
    SELF_SUSPECT.include?(result.status) && harness?(result)
  end

  def harness?(result)
    Kimera::SelfProtection.new(result.file).critical?
  end

  def detail(status)
    "#{status == :survived ? "unfalsifiable warm survivor" : "self-crash"} in the in-process runner " \
      "(warm #{status}); evaluate with --isolated"
  end
end
