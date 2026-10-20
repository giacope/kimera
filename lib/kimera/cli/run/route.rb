# frozen_string_literal: true

require_relative "../../self_protection"

class Kimera::CLI::Run::Route
  def initialize(registry, options)
    @registry = registry
    @options = options
  end

  def split(ids, &coverage) = ids.partition { |id| apart?(id, coverage) }

  def judging?
    chosen = @options[:judge_isolated_only]
    chosen.nil? ? !@options[:since].nil? : chosen
  end

  private

  def apart?(id, coverage) = critical?(id) || patterns.any? { |pattern| matches?(coverage.call, id, pattern) }

  def patterns = Array(@options[:isolate_when_covered_by])

  def critical?(id) = Kimera::SelfProtection.new(@registry.index.fetch(id).file).critical?

  def matches?(coverage, id, pattern)
    tests = coverage.fetch(id) { coverage.fetch(id.to_s, []) }
    tests.any? { |test| test.include?(pattern) }
  end
end
