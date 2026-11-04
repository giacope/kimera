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
    safe, unsafe = ids.partition { |id| @verdicts.point(id).fits?(safe: true) }
    [safe, *unsafe.partition { |id| @verdicts.point(id).reasons(Kimera::Reason.unreloadable).empty? }]
  end

  def quarantine(id)
    found = @verdicts.point(id)
    @verdicts.unjudged(id, found.reasons(Kimera::Reason.unsafety).first).with(status: held(found))
  end

  def reclassified(results) = results.transform_values { |result| reclassify(result) }

  private

  def held(point)
    return :unmutatable if point.reasons(Kimera::Reason.unmutatable).any?
    point.reasons(Kimera::Reason.unloaded).any? ? :no_coverage : :isolated_only
  end

  def reclassify(result) = result.suspected(SELF_SUSPECT) { |status, file| harness?(file) && detail(status) }

  def harness?(file)
    Kimera::SelfProtection.new(file).critical?
  end

  def detail(status)
    "#{status == :survived ? "unfalsifiable warm survivor" : "self-crash"} in the in-process runner " \
      "(warm #{status}); evaluate with --isolated"
  end
end
