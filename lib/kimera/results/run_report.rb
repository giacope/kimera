# frozen_string_literal: true

require_relative "../rewrite/directive"
require_relative "result"

module Kimera
  LeakReport = Struct.new(:mutant_id, :detail, keyword_init: true)
end

class Kimera::RunReport
  attr_reader :results, :leaks, :registry, :tests

  CONDITIONAL = %i[harness_error ignored isolated_only unmutatable leaks].freeze
  LABELS = { total: "mutants", harness_error: "unjudged" }.freeze
  SCHEMA_VERSION = 1

  def initialize(results:, leaks: [], registry: nil, tests: {})
    @results = results
    @leaks = leaks
    @registry = registry
    @tests = tests
  end

  def statuses(status)
    grouped.fetch(status, [])
  end

  def merge(other) = rebuilt(results: @results + other.results, tests: @tests.merge(other.tests))

  def revise(revised)
    fresh = revised.to_h { |judged| [judged.mutant_id, judged] }
    rebuilt(results: @results.map { |result| fresh.fetch(result.mutant_id, result) })
  end

  def described(tests) = rebuilt(tests: @tests.merge(tests))

  def test_ids = @results.flat_map { |result| Array(result.covering_tests) + Array(result.failing_tests) }.uniq

  def test(id) = @tests.fetch(id, {})

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

  def errors
    statuses(:harness_error)
  end

  def covered
    @results.select(&:covered?)
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
      .merge(catalog)
  end

  private

  def catalog
    listed = @tests.slice(*test_ids)
    listed.empty? ? {} : { "tests" => listed }
  end

  def scoreline
    return "score=n/a (nothing to mutate)" if @results.empty?
    return "score=n/a (0 of #{@results.size} mutants evaluated)" if covered.empty?
    text = "score=#{percent}"
    count = uncovered.size
    count.positive? ? "#{text} (#{count} uncovered not scored)" : text
  end

  def grouped
    @_grouped ||= @results.group_by(&:status)
  end

  def detailed(result)
    base = result.to_h
    id = result.mutant_id
    pair = @registry&.point(id)
    pair ? base.merge("key" => @registry.keys[id]).merge(rewritten(pair)) : base
  end

  def rewritten(pair)
    mutant, point = pair
    place(point, mutant).merge(rendered(point.original_source, mutant))
  end

  def rendered(original, mutant)
    { "original" => original, "mutated" => Kimera::Rewrite::Directive.render(original, mutant.directive) }
  end

  def place(point, mutant)
    point.location.position.merge("method" => point.method_name, "operator" => point.operator, "label" => mutant.label)
  end

  def rebuilt(results: @results, tests: @tests)
    Kimera::RunReport.new(results: results, leaks: @leaks, registry: @registry, tests: tests)
  end
end
