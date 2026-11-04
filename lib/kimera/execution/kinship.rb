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
    _mutant, point, file = @registry[id] { return tests.uniq }
    (related(point, file) & tests) | tests
  end

  private

  def related(point, file)
    siblings = @registry.to_h.fetch(file, []).sort_by { |other| other.fits?(kin: point) ? 0 : 1 }
    known = @coverage.to_h
    siblings.flat_map { |other| other.each.flat_map { |mutant| Array(known[mutant.to_i]) } }
  end
end
