# frozen_string_literal: true

require_relative "../registry/mutation_point"
require_relative "../runtime"
require_relative "null_progress"
require_relative "standard_streams"
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

  def initialize(registry, adapter, **options)
    @registry = registry
    @adapter = adapter
    @options = options
  end

  def follow!(coverage, scope: nil, progress: Kimera::Execution::NullProgress.new)
    return NONE unless wanted?(scope, coverage)
    progress.note(NOTE)
    run = hatching.call { traced }
    -> { progress.during(1, WAIT) { |tick| tick.call.tap { mark!(run, coverage) } } }
  end

  def mark!(run, coverage)
    seen = sightings(run) { return }
    @registry.index.each { |id, point| verdict(point, covering(id, coverage), seen[id]) }
  end

  def wanted?(scope, coverage)
    scope.nil? || scope.any? { |id| open?(@registry.index[id], coverage) } || cheap?(scope, coverage)
  end

  private

  def open?(point, coverage)
    point&.fits?(safe: true) && point.each.any? { |mutant| covering(mutant.to_i, coverage).empty? }
  end

  def cheap?(scope, coverage)
    judged = scope.sum { |id| covering(id, coverage).sum { |test| timings.fetch(test, 0.0) } }
    judged.positive? && timings.values.sum * @options.fetch(:jobs, 1) <= judged
  end

  def timings = @options.fetch(:timings, {})

  def verdict(point, cover, seen)
    reason = judgement(cover, seen)
    point.mark!(reason) if reason && point.fits?(safe: true)
  end

  def judgement(cover, seen)
    return (Kimera::Reason.ordered unless seen.empty?) if cover.empty?
    return Kimera::Reason.masked if seen.empty?
    Kimera::Reason.trailed if (cover - seen).empty? && (seen - cover).any?
  end

  def hatching(cells = Kimera::Execution::Zygote) = cells.new.method(:hatch)

  def traced(runtime = Kimera::RUNTIME, streams = Kimera::Execution::StandardStreams.new)
    ledger = Kimera::Runtime::Ledger.new
    streams.quietly { @adapter.test_ids.to_h { |test| [test, touches(test, ledger, runtime)] } }
  end

  def touches(test, ledger, runtime)
    runtime.during(nil, ledger) { @adapter.run([test]) }
    ledger.drain!
  end

  def sightings(run)
    found = Hash.new { |table, id| table[id] = [] }
    run.call.each { |test, ids| ids.each { |id| found[id] << test } }
    found
  rescue Kimera::Execution::Zygote::Died, Kimera::Execution::Zygote::Raised, Timeout::Error
    yield
  end

  def covering(id, coverage) = coverage.fetch(id) { coverage.fetch(id.to_s, []) }
end
