# frozen_string_literal: true

require_relative "../test_quality"

class Kimera::RunReport::Notes
  def initialize(results, registry, context)
    @results = results
    @registry = registry
    @context = context
  end

  def test(id) = tests.fetch(id, {})

  def test_ids
    flaky = Array(@context[:flaky]&.fetch("flaky")).map { |flake| flake.fetch("test") } + Array(@context[:suite])
    @results.flat_map { |result| result.to_h.values_at("covering_tests", "failing_tests", "killing_tests") }
      .flat_map { |tests| Array(tests) }.concat(flaky).uniq
  end

  def quality = @context[:suite]&.then { |suite| Kimera::TestQuality.new(@results, suite).to_h }

  def remark(remarks)
    @registry.regions { |found| remarks.regions(found) }
  end

  def to_h
    { "tests" => tests, "flaky" => @context[:flaky], "suite" => @context[:suite] }
      .merge("phases" => @context[:phases]).compact
  end

  private

  def tests = @context.fetch(:tests, {})
end
