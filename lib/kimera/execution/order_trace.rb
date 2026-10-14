# frozen_string_literal: true

require_relative "../registry/mutation_point"
require_relative "null_progress"
require_relative "zygote"

module Kimera
  module Execution
  end
end

class Kimera::Execution::OrderTrace
  ORDERED = Kimera::MutationPoint::ORDER_REASON
  NOTE = "baseline (whole suite, in order)"

  def initialize(registry)
    @registry = registry
  end

  def follow!(baseline, coverage, scope: nil, progress: Kimera::Execution::NullProgress)
    return unless wanted?(scope, coverage)
    progress.note(NOTE)
    mark!(baseline, coverage)
  end

  def mark!(baseline, coverage)
    reached(baseline).each do |id|
      point = @registry.point(id)&.last
      point.revisit!(ORDERED) if point&.safe? && uncovered?(id, coverage)
    end
  end

  def wanted?(scope, coverage) = scope.nil? || scope.any? { |id| open?(@registry.point(id)&.last, coverage) }

  private

  def open?(point, coverage) = point&.safe? && point.ids.any? { |id| uncovered?(id, coverage) }

  def reached(baseline)
    Array(baseline.sequence["touched"])
  rescue Kimera::Execution::Zygote::Died, Kimera::Execution::Zygote::Raised, Timeout::Error
    []
  end

  def uncovered?(id, coverage) = coverage.fetch(id) { coverage.fetch(id.to_s, []) }.empty?
end
