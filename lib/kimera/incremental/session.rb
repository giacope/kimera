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
    def load(path, registry: nil)
      return new unless path && File.exist?(path)
      session = decode(JSON.parse(File.read(path)))
      session.prune!(registry) if registry
      session
    end

    def decode(data)
      new(**attributes(data))
    end

    def attributes(data)
      attrs = { leaks: leaks(data["leaks"]), meta: data["meta"] || {} }
      attrs[:results] = keys(data["results"]) { |hash| Kimera::MutantResult.from_h(hash) }
      attrs[:fingerprints] = keys(data["fingerprints"]) { |fingerprint| fingerprint }
      attrs
    end

    def leaks(raw)
      Array(raw).map { |hash| Kimera::LeakReport.new(mutant_id: hash["mutant_id"], detail: hash["detail"]) }
    end

    def keys(hash)
      Hash(hash).to_h { |id, value| [Integer(id, 10), yield(value)] }
    end

    def fingerprint(registry, id)
      pair = registry.point(id)
      return unless pair
      mutant, point = pair
      [point.file, point.location.start_line, point.original_source, mutant.label].join(" ")
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
    results += waived.map { |id| Kimera::MutantResult.waived(id, registry.index[id]&.file) }
    Kimera::RunReport.new(results: results, leaks: @leaks, registry: registry)
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
    !stored || stored != self.class.fingerprint(registry, id)
  end

  def payload
    base.merge("fingerprints" => @fingerprints.transform_keys(&:to_s), "leaks" => @leaks.map(&:to_h))
  end

  def base
    { "version" => VERSION, "meta" => @meta, "results" => @results.transform_keys(&:to_s).transform_values(&:to_h) }
  end

  def fingerprints(registry)
    @results.keys.each_with_object({}) do |id, hash|
      fingerprint = self.class.fingerprint(registry, id)
      hash[id] = fingerprint if fingerprint
    end
  end
end
