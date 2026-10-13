# frozen_string_literal: true

require_relative "../registry/mutation_point"
require_relative "zygote"

module Kimera
  module Execution
  end
end

class Kimera::Execution::OrderTrace
  ORDERED = Kimera::MutationPoint::ORDER_REASON

  def initialize(registry)
    @registry = registry
  end

  def mark!(baseline, coverage)
    reached(baseline).each do |id|
      point = @registry.point(id)&.last
      point.revisit!(ORDERED) if point&.safe? && uncovered?(id, coverage)
    end
  end

  private

  def reached(baseline)
    Array(baseline.sequence["touched"])
  rescue Kimera::Execution::Zygote::Died, Kimera::Execution::Zygote::Raised, Timeout::Error
    []
  end

  def uncovered?(id, coverage) = coverage.fetch(id) { coverage.fetch(id.to_s, []) }.empty?
end
