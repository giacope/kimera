# frozen_string_literal: true

require_relative "../registry/mutation_point"
require_relative "null_progress"
require_relative "zygote"

module Kimera
  module Execution
  end
end

class Kimera::Execution::OrderTrace
  NOTE = "baseline (whole suite, in order, beside the mutants)"
  WAIT = "baseline (in order)"
  NONE = proc {}
  private_constant(:NONE)

  def initialize(registry)
    @registry = registry
  end

  def follow!(baseline, coverage, scope: nil, progress: Kimera::Execution::NullProgress.new)
    return NONE unless wanted?(scope, coverage)
    progress.note(NOTE)
    run = baseline.sequence(hatching)
    -> { progress.during(1, WAIT) { |tick| tick.call.tap { mark!(run, coverage) } } }
  end

  def mark!(run, coverage)
    reached(run) { [] }.each do |id|
      point = @registry.index[id]
      point.mark!(Kimera::Reason.ordered) if point&.fits?(safe: true) && uncovered?(id, coverage)
    end
  end

  def wanted?(scope, coverage) = scope.nil? || scope.any? { |id| open?(@registry.index[id], coverage) }

  private

  def open?(point, coverage)
    point&.fits?(safe: true) && point.each.any? { |mutant| uncovered?(mutant.to_i, coverage) }
  end

  def hatching(cells = Kimera::Execution::Zygote) = cells.new.method(:hatch)

  def reached(run)
    Array(run.call["touched"])
  rescue Kimera::Execution::Zygote::Died, Kimera::Execution::Zygote::Raised, Timeout::Error
    yield
  end

  def uncovered?(id, coverage) = coverage.fetch(id) { coverage.fetch(id.to_s, []) }.empty?
end
