# frozen_string_literal: true

require "json"
require_relative "../results/result"
require_relative "../results/run_report"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::Session
  VERSION = 2

  attr_reader :results, :leaks

  def initialize(results: {}, leaks: [], meta: {}, fingerprints: {})
    @results = results
    @leaks = leaks
    @meta = meta
    @fingerprints = fingerprints
  end

  class << self
    def from(path, registry: nil)
      return new unless path && File.exist?(path)
      data = JSON.parse(File.read(path, encoding: Encoding::UTF_8))
      session = Kimera::Incremental::Session::Payload.new(data).session
      registry ? session.prune!(registry) : session
    end
  end

  def prune!(registry)
    @results.reject! { |id, _| stale?(id, registry) }
    @leaks.select! { |leak| @results.key?(leak.mutant_id) }
    self
  end

  def done?(id)
    @results.key?(id)
  end

  def report(evaluated, waived, registry)
    results = evaluated.filter_map { |id| @results[id] }
    results += waived.map { |id| waiver(id, registry) }
    Kimera::RunReport.new(results: results, leaks: @leaks, registry: registry)
  end

  def waiver(id, registry)
    @results[id]&.waive || Kimera::MutantResult.from_waiver(id, registry.index[id]&.file)
  end

  def merge!(report)
    report.results.each { |r| @results[r.mutant_id] = r }
    @leaks.concat(report.leaks)
    self
  end

  def save(path, registry: nil, meta: {})
    @meta = @meta.merge(meta)
    @fingerprints = fingerprints(registry) if registry
    File.write(path, JSON.pretty_generate(payload))
    path
  end

  private

  def stale?(id, registry)
    stored = @fingerprints[id]
    !stored || stored != fingerprint(registry.point(id))
  end

  def payload
    base.merge("fingerprints" => @fingerprints.transform_keys(&:to_s), "leaks" => @leaks.map(&:to_h))
  end

  def base
    { "version" => VERSION, "meta" => @meta, "results" => @results.transform_keys(&:to_s).transform_values(&:to_h) }
  end

  def fingerprints(registry)
    @results.keys.each_with_object({}) do |id, hash|
      stamp = fingerprint(registry.point(id))
      hash[id] = stamp if stamp
    end
  end

  def fingerprint(pair)
    return unless pair
    mutant, point = pair
    [point.file, point.location.start_line, point.original_source, mutant.label].join(" ")
  end
end

require_relative "session/payload"
