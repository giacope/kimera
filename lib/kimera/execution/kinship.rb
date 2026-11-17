# frozen_string_literal: true

require_relative "../registry/mutation_point"
require_relative "pace"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Kinship
  def initialize(registry, coverage, pace = Kimera::Execution::Pace.new({}))
    @registry = registry
    @coverage = coverage
    @pace = pace
  end

  def order(id, tests)
    _mutant, point, file = @registry[id] { return tests.uniq }
    near, far = @registry.to_h.fetch(file, []).partition { |other| other.fits?(kin: point) }
    [near, far].flat_map { |points| @pace.fastest(reaching(points) & tests) } | @pace.fastest(tests)
  end

  private

  def reaching(points)
    known = @coverage.to_h
    points.flat_map { |other| other.each.flat_map { |mutant| Array(known[mutant.to_i]) } }
  end
end
