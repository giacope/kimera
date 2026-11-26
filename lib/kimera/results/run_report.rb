# frozen_string_literal: true

require_relative "../registry/registry"
require_relative "report_rows"
require_relative "result"

class Kimera::RunReport
  include Enumerable

  SCHEMA_VERSION = 2

  def initialize(results:, registry: Kimera::Registry.new, **context)
    @results = results
    @registry = registry
    @context = context
  end

  def each(&) = @results.each(&)

  def revise(revised) = rebuilt(results: @results.to_h(&:entry).merge(revised.to_a.to_h(&:entry)).values)

  def annotate(**changes) = rebuilt(**changes, tests: @context.fetch(:tests, {}).merge(changes.fetch(:tests, {})))

  def score = Kimera::RunReport::Score.new(@results, @context.fetch(:counted, []))

  def notes = Kimera::RunReport::Notes.new(@results, @registry, @context)

  def unmutated = @registry.regions(&:size)

  def to_h
    rows = Kimera::ReportRows.new(@registry)
    tally = score
    { "schema_version" => SCHEMA_VERSION, "counts" => tally.to_h, "mutation_score" => tally.to_f }
      .merge("results" => @results.map { |result| rows.of(result) })
      .merge("unmutated" => @registry.regions { |found| found.map(&:to_h) })
      .merge(noted).merge({ "run" => @context[:run] }.compact)
  end

  private

  def noted
    found = notes
    named = found.to_h
    listed = named.fetch("tests").slice(*found.test_ids)
    (listed.empty? ? {} : { "tests" => listed })
      .merge({ "test_quality" => found.quality, "flaky_tests" => named["flaky"], "phases" => named["phases"] }.compact)
  end

  def rebuilt(results: @results, **changes)
    Kimera::RunReport.new(results: results, registry: @registry, **@context, **changes)
  end
end

require_relative "run_report/score"
require_relative "run_report/notes"
