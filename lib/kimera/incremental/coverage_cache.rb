# frozen_string_literal: true

require_relative "coverage_map"
require_relative "fingerprint"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::CoverageCache
  PATH = "tmp/kimera/coverage.json"
  MISSING = "none is stored at #{PATH}; a full run with --reuse-coverage stores one".freeze

  def initialize(registry:, options:, sources:, errors: $stderr)
    @registry = registry
    @options = options
    @sources = sources
    @errors = errors
  end

  def measured(ids)
    return ids unless @options[:reuse_coverage] && @options[:since]
    stored = Kimera::Incremental::CoverageMap.read(path)
    reasons = stored.mismatches(fingerprint)
    reasons.empty? ? chosen(stored, ids) : everything(ids, reasons.fetch(0))
  rescue Errno::ENOENT
    everything(ids, MISSING)
  rescue JSON::ParserError
    everything(ids, "#{PATH} is not JSON")
  end

  def keep(harness, adapter)
    return unless @options[:reuse_coverage] && !@options[:since]
    tests = adapter.test_ids
    measured = { "coverage" => by_file(harness.coverage), "tests" => tests }
      .merge("test_files" => tests.to_h { [it, adapter[it].file] })
    Kimera::Incremental::CoverageMap.new(fingerprint.merge(measured)).write(path)
  end

  private

  def root = @options.to_h.fetch(:source_root)

  def path = File.expand_path(PATH, root)

  def fingerprint
    @_fingerprint ||= Kimera::Incremental::Fingerprint.new(root: root, options: @options, sources: @sources.call).to_h
  end

  def everything(ids, reason)
    ids.tap { @errors.puts("kimera: not reusing the stored coverage map: #{reason}; the baseline runs every test") }
  end

  def chosen(stored, ids)
    sources = fingerprint["sources"]
    stored.picked(sources, @registry.to_h.keys, ids).tap do |picked|
      @errors.puts(stored.reused(sources, picked.size, ids.size))
    end
  end

  def by_file(coverage)
    own = @registry.each.select { |mutant, _point, _file| coverage.key?(mutant.to_i) }
    own.each_with_object(Hash.new { |files, file| files[file] = [] }) do |(mutant, _point, file), files|
      files[file] |= coverage.fetch(mutant.to_i)
    end
  end
end
