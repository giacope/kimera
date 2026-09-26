# frozen_string_literal: true

require_relative "../registry/mutation_point"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Kinship
  def initialize(registry, coverage)
    @registry = registry
    @coverage = coverage
  end

  def order(id, tests)
    (related(@registry.index.fetch(id, Kimera::MutationPoint::NONE)) & tests) | tests
  end

  private

  def related(point)
    siblings = @registry.at(point.file).sort_by { |other| other.method_name == point.method_name ? 0 : 1 }
    known = @coverage.to_h
    siblings.flat_map { |other| other.ids.flat_map { |mutant| Array(known[mutant]) } }
  end
end
