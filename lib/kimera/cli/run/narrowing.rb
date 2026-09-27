# frozen_string_literal: true

require_relative "../../scope/file_set"

class Kimera::CLI
end

class Kimera::CLI::Run
end

class Kimera::CLI::Run::Narrowing
  def initialize(options)
    @options = options
  end

  def narrowed?
    kept, total = counts
    kept < total
  end

  def provenance
    narrowed? ? { "narrowed" => true, "configured_tests" => @options[:configured_tests] } : { "narrowed" => false }
  end

  def note
    return unless narrowed?
    kept, total = counts
    "narrowed run: --tests matched #{count(kept)} of #{count(total)} test files from the configured tests: " \
      "glob; survivors may be killed by tests outside it"
  end

  private

  def counts = @_counts ||= measure

  def measure
    tests, configured = @options.values_at(:tests, :configured_tests)
    return [0, 0] if tests == configured
    all = files(configured)
    [(all & files(tests)).size, all.size]
  end

  def files(globs)
    Kimera::FileSet.expand(globs, exclude: @options[:exclude_tests]).map { |file| File.expand_path(file) }
  end

  def count(number) = number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
end
