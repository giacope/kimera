# frozen_string_literal: true

require "pathname"
require_relative "coverage_map"
require_relative "fingerprint"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::CoverageCache
  PATH = "tmp/kimera/coverage.json"
  SHARED = /\bshared_(?:examples_for|examples|context)\b/

  def initialize(registry:, options:, sources:, errors: $stderr)
    @registry = registry
    @options = options
    @sources = sources
    @errors = errors
  end

  def measured(ids)
    return ids unless @options[:reuse_coverage] && !whole?
    stored = Kimera::Incremental::CoverageMap.read(path)
    reasons = outside + stored.mismatches(fingerprint, own)
    reasons.empty? ? chosen(stored, ids) : everything(ids, reasons.fetch(0))
  rescue Errno::ENOENT
    ids
  rescue JSON::ParserError
    everything(ids, "#{PATH} is not JSON")
  end

  def keep(harness, adapter)
    return unless @options[:reuse_coverage] && whole?
    tests = adapter.test_ids
    measured = { "coverage" => by_file(harness.coverage), "tests" => tests }
      .merge("test_files" => tests.to_h { [it, relative(adapter[it].file)] })
    Kimera::Incremental::CoverageMap.new(fingerprint.merge(measured)).write(path)
  end

  private

  def root = @options.to_h.fetch(:source_root)

  def path = File.expand_path(PATH, root)

  def settled = { paths: @options[:configured_paths], tests: @options[:configured_tests] }.compact

  def whole?
    tests = @options.to_h.fetch(:configured_tests) { @options[:tests] }
    !@options[:since] && tests == @options[:tests] && @sources.call(:paths) == @sources.call(:configured_paths)
  end

  def fingerprint
    @_fingerprint ||= Kimera::Incremental::Fingerprint.new(
      root: root, options: @options.to_h.merge(settled), sources: @sources.call(:configured_paths)
    ).to_h
  end

  def outside
    known = fingerprint["sources"]
    @registry.to_h.keys.reject { known.key?(it) }.first(1).map { "#{it} lies outside the configured paths it covers" }
  end

  def own
    tests = Dir.glob(@options.to_h.merge(settled).fetch(:tests), base: root).to_set
    ->(file) { tests.include?(file) && !File.read(File.join(root, file), encoding: Encoding::UTF_8).match?(SHARED) }
  end

  def relative(file)
    base = Pathname(File.expand_path(root))
    Pathname(File.expand_path(file, base)).relative_path_from(base).to_s
  end

  def everything(ids, reason)
    ids.tap { @errors.puts("kimera: not reusing the stored coverage map: #{reason}; the baseline runs every test") }
  end

  def chosen(stored, ids)
    current = fingerprint
    owned = own
    stored.picked(current, @registry.to_h.keys, ids, owned).tap do |picked|
      @errors.puts(stored.reused(current, picked.size, ids.size, owned))
    end
  end

  def by_file(coverage)
    reached = @registry.each.select { |mutant, _point, _file| coverage.key?(mutant.to_i) }
    reached.each_with_object(Hash.new { |files, file| files[file] = [] }) do |(mutant, _point, file), files|
      files[file] |= coverage.fetch(mutant.to_i)
    end
  end
end
