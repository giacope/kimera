# frozen_string_literal: true

require_relative "../rewrite/directive"
require_relative "result"

module Kimera
  LeakReport = Struct.new(:mutant_id, :detail, keyword_init: true)
end

class Kimera::RunReport
  attr_reader :results, :leaks, :registry

  CONDITIONAL = %i[harness_error ignored isolated_only leaks].freeze
  LABELS = { total: "mutants", harness_error: "unjudged" }.freeze
  SCHEMA_VERSION = 1

  def initialize(results:, leaks: [], registry: nil)
    @results = results
    @leaks = leaks
    @registry = registry
  end

  def statuses(status)
    grouped.fetch(status, [])
  end

  def merge(other)
    Kimera::RunReport.new(results: @results + other.results, leaks: @leaks, registry: @registry)
  end

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
  end

  private

  def scoreline
    return "score=n/a (0 of #{@results.size} mutants evaluated)" if covered.empty? && !@results.empty?
    text = format("score=%.1f%%", score * 100)
    count = uncovered.size
    count.positive? ? "#{text} (#{count} uncovered not scored)" : text
  end

  def grouped
    @_grouped ||= @results.group_by(&:status)
  end

  def detailed(result)
    base = result.to_h
    pair = @registry&.point(result.mutant_id)
    pair ? base.merge(rewritten(pair)) : base
  end

  def rewritten(pair)
    mutant, point = pair
    place(point, mutant).merge(rendered(point.original_source, mutant))
  end

  def rendered(original, mutant)
    { "original" => original, "mutated" => Kimera::Rewrite::Directive.render(original, mutant.directive) }
  end

  def place(point, mutant)
    { "line" => point.location.start_line, "operator" => point.operator, "label" => mutant.label }
  end
end
