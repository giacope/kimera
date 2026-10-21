# frozen_string_literal: true

require_relative "coverage_map"
require_relative "fingerprint"

module Kimera
  module Incremental
  end
end

# --reuse-coverage. A full run stores its baseline's coverage map. A --since
# run whose Ruby, settings, tests, support and config files match the stored
# map's runs only the baseline tests that reached a source file changed since
# the map was built or one in scope, and tests the map does not know: every
# test that can cover an in-scope mutant gets a fresh baseline. Otherwise it
# runs the full baseline and says why.
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
    reason = stored.mismatch(fingerprint)
    reason ? everything(ids, reason) : chosen(stored, ids)
  rescue Errno::ENOENT
    everything(ids, MISSING)
  rescue JSON::ParserError
    everything(ids, "#{PATH} is not JSON")
  end

  def keep(harness, adapter)
    return unless @options[:reuse_coverage] && !@options[:since]
    measured = { "coverage" => by_file(harness.coverage), "tests" => adapter.test_ids }
    Kimera::Incremental::CoverageMap.new(fingerprint.merge(measured)).write(path)
  end

  private

  def root = @options.fetch(:source_root)

  def path = File.expand_path(PATH, root)

  def fingerprint
    @_fingerprint ||= Kimera::Incremental::Fingerprint.new(root: root, options: @options, sources: @sources.call).to_h
  end

  def everything(ids, reason)
    @errors.puts("kimera: not reusing the stored coverage map: #{reason}; the baseline runs every test")
    ids
  end

  def chosen(stored, ids)
    changed = stored.changed(fingerprint["sources"])
    stored.tests(changed | @registry.files, ids).tap do |picked|
      @errors.puts(
        "kimera: reusing the coverage map from #{stored.commit} (#{changed.size} source file(s) changed since): " \
          "the baseline runs #{picked.size} of #{ids.size} tests"
      )
    end
  end

  def by_file(coverage)
    coverage.each_with_object(Hash.new { |files, file| files[file] = [] }) do |(id, tests), files|
      files[@registry.index.fetch(id).file] |= tests
    end
  end
end
