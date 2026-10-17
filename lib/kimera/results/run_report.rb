# frozen_string_literal: true

require_relative "report_rows"
require_relative "result"

module Kimera
  LeakReport =
    Struct.new(:mutant_id, :detail, keyword_init: true) do
      def line = "- ##{mutant_id}  #{detail}"
    end
end

class Kimera::RunReport
  include Kimera::ReportRows

  Notes = Data.define(:counted, :flaky, :suite)
  NOTES = Notes.new(counted: [], flaky: nil, suite: nil)

  attr_reader :results, :leaks, :registry

  CONDITIONAL = %i[uncovered_by_unit harness_error ignored isolated_only unmutatable leaks].freeze
  LABELS = { total: "mutants", harness_error: "unjudged" }.freeze
  SCHEMA_VERSION = 1

  def initialize(results:, leaks: [], registry: nil, **context)
    @results = results
    @leaks = leaks
    @registry = registry
    @context = context
  end

  def tests = @context.fetch(:tests, {})

  def notes = NOTES.with(**@context.except(:tests))

  def statuses(status)
    grouped.fetch(status, [])
  end

  def merge(other) = rebuilt(results: @results + other.results, tests: tests.merge(other.tests))

  def revise(revised)
    fresh = revised.to_h { |judged| [judged.mutant_id, judged] }
    rebuilt(results: @results.map { |result| fresh.fetch(result.mutant_id, result) })
  end

  def described(named) = rebuilt(tests: tests.merge(named))

  def annotate(**changes) = rebuilt(**changes)

  def counting(statuses) = annotate(counted: statuses)

  def counted = notes.counted

  def test_ids
    found = notes
    flaky = Array(found.flaky&.fetch("flaky")).map { |flake| flake.fetch("test") } + Array(found.suite)
    @results.flat_map { |result| [*result.covering_tests, *result.failing_tests, *result.killing_tests] }
      .concat(flaky).uniq
  end

  def test(id) = tests.fetch(id, {})

  def unmutated = @registry ? @registry.unmutated : []

  def by_file = @results.group_by { |result| result.file.to_s }.transform_values { |part| rebuilt(results: part) }

  def killed
    @results.select(&:killed?)
  end

  def survived
    statuses(:survived)
  end

  def uncovered
    statuses(:no_coverage)
  end

  def unattributed = statuses(:uncovered_by_unit)

  def errors
    statuses(:harness_error)
  end

  def covered
    @results.select { |result| result.covered? || @context.fetch(:counted, []).include?(result.status) }
  end

  def score
    total = covered.size
    return 1.0 if total.zero?
    Float(killed.size) / total
  end

  def percent = covered.empty? ? "n/a" : format("%.1f%%", score * 100)

  def counts
    { total: @results.size, killed: killed.size, leaks: @leaks.size, **reported }
  end

  def reported
    Kimera::Status::REPORTED.to_h { |status| [status, statuses(status).size] }
  end

  def summary
    tallies = counts
    tallies.keys.filter_map { |key| labeled(key) }.insert(tallies.size - CONDITIONAL.size, scoreline).join(" ")
  end

  def labeled(key)
    count = counts[key]
    return if CONDITIONAL.include?(key) && count.zero?
    "#{LABELS.fetch(key, key)}=#{count}"
  end

  def document(metadata) = metadata ? to_h.merge("run" => metadata) : to_h

  def to_h
    { "schema_version" => SCHEMA_VERSION, "counts" => counts, "mutation_score" => score }
      .merge("results" => @results.map { |result| detailed(result) }, "leaks" => @leaks.map(&:to_h))
      .merge("unmutated" => unmutated.map(&:to_h)).merge(catalog).merge(flakes)
  end

  private

  def catalog
    listed = tests.slice(*test_ids)
    listed.empty? ? {} : { "tests" => listed }
  end

  def scoreline
    return "score=n/a (nothing to mutate)" if @results.empty?
    return "score=n/a (0 of #{@results.size} mutants evaluated)" if covered.empty?
    text = "score=#{percent}"
    count = uncovered.size
    return text unless count.positive?
    return "#{text} (#{count} uncovered scored as not killed)" if @context.fetch(:counted, []).include?(:no_coverage)
    "#{text} (#{count} uncovered not scored)"
  end

  def grouped
    @_grouped ||= @results.group_by(&:status)
  end

  def rebuilt(results: @results, **changes)
    Kimera::RunReport.new(results: results, leaks: @leaks, registry: @registry, **@context, **changes)
  end
end
