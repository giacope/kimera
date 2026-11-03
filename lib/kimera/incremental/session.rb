# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../results/result"
require_relative "../results/run_report"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::Session
  VERSION = 3

  def initialize(results: {}, leaks: [], meta: {}, fingerprints: {})
    @results = results
    @leaks = leaks
    @meta = meta
    @fingerprints = fingerprints
  end

  class << self
    def from(path, stamp: nil)
      stored = path && File.exist?(path) ? JSON.parse(File.read(path, encoding: Encoding::UTF_8)) : {}
      Kimera::Incremental::Session::Payload.new(stored).session(stamp)
    end
  end

  def pruned(registry)
    kept = @results.reject { |id, _| stale?(id, registry) }
    self.class.new(
      results: kept, leaks: @leaks.select { |leak| kept.key?(leak.mutant_id) }, meta: @meta, fingerprints: @fingerprints
    )
  end

  def judged(todo)
    remaining = todo.reject { |id| @results.key?(id) }
    remaining.empty? ? self : merged(yield(remaining))
  end

  def report(evaluated, waived, registry)
    results = evaluated.filter_map { |id| @results[id] }
    results += waived.map { |id| waiver(id, registry) }
    Kimera::RunReport.new(results: results, leaks: @leaks, registry: registry, tests: tests)
      .annotate(flaky: @meta["flaky"], suite: @meta["suite"])
  end

  def save(path, registry, meta: {})
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(payload(@meta.merge(meta), fingerprints(registry))))
    self
  end

  private

  def waiver(id, registry)
    @results[id]&.waive || Kimera::MutantResult.from_waiver(id, registry.index[id]&.file)
  end

  def merged(report)
    named = report.tests
    meta = named.empty? ? @meta : @meta.merge("tests" => tests.merge(named))
    self.class.new(
      results: @results.merge(report.results.to_h { |result| [result.mutant_id, result] }),
      leaks: @leaks + report.leaks, meta: meta.merge(noted(report.notes)), fingerprints: @fingerprints
    )
  end

  def noted(notes) = { "flaky" => notes.flaky, "suite" => notes.suite }.compact

  def tests = @meta.fetch("tests", {})

  def stale?(id, registry)
    stored = @fingerprints[id]
    !stored || stored != fingerprint(registry.point(id) { return true })
  end

  def payload(meta, fingerprints)
    base(meta).merge("fingerprints" => fingerprints.transform_keys(&:to_s), "leaks" => @leaks.map(&:to_h))
  end

  def base(meta)
    { "version" => VERSION, "meta" => meta, "results" => @results.transform_keys(&:to_s).transform_values(&:to_h) }
  end

  def fingerprints(registry)
    @results.keys.select { |id| registry.index.key?(id) }.to_h { |id| [id, fingerprint(registry.point(id))] }
  end

  def fingerprint(pair)
    mutant, point = pair
    [point.file, point.location.start_line, point.original_source, mutant.label].join(" ")
  end
end

require_relative "session/payload"
