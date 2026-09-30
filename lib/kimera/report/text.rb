# frozen_string_literal: true

require_relative "../rewrite/directive"
require_relative "coloring"
require_relative "screen"
require_relative "sections"
require_relative "actions"

module Kimera
  module Report
  end
end

class Kimera::Report::Text
  include Kimera::Report::Coloring
  include Kimera::Report::Sections

  MAX_TESTS_SHOWN = 5

  def initialize(registry, io: $stdout, color: nil)
    @registry = registry
    @io = io
    @color = color
  end

  COVERAGE_SECTIONS = { hint: :hint, list: :missing }.freeze

  def report(report, scope: nil, coverage: :hint, path: nil)
    header(report, scope)
    survivors(report)
    __send__(COVERAGE_SECTIONS.fetch(coverage), report, path)
    leaks(report.leaks)
    Kimera::Report::Actions.new(io: @io).show(report, path: path)
  end

  private

  def header(report, scope)
    @io.puts(scope) if scope
    @io.puts(summary(report))
  end

  def survivors(report)
    section("Surviving mutants", report.survived) { |result| survivor(result) }
    unjudged(report)
    waivers(report)
    rejudged(report)
  end

  def summary(report)
    bold(report.summary)
  end

  def section(title, results, &)
    heading(title, results.sort_by(&:mutant_id)).each(&)
  end

  def heading(title, listed)
    return listed if listed.empty?
    @io.puts
    @io.puts(bold("#{title} (#{listed.size}):"))
    listed
  end

  def survivor(result)
    resolved(result) { |id, mutant, point| display(id, mutant, point, result) }
  end

  def display(id, mutant, point, result)
    @io.puts
    spotted("survived", id, mutant, point)
    diff(point, mutant)
    covering(result)
    annotate(result)
  end

  def resolved(result)
    id = result.mutant_id
    pair = @registry.point(id)
    yield(id, *pair) if pair
  end

  def diff(point, mutant)
    original = point.original_source
    variant = Kimera::Rewrite::Directive.render(original, mutant.directive)
    source(red("-"), original)
    source(green("+"), variant) if variant
  end

  def source(sign, text)
    first, *rest = text.split("\n")
    @io.puts("    #{sign} #{first}")
    rest.each { |line| @io.puts("      #{line}") }
  end

  def covering(result)
    tests = Array(result.covering_tests)
    return if tests.empty?
    @io.puts("    covered by #{tests.size} test(s): #{names(tests)}")
  end

  def names(tests)
    shown = tests.first(MAX_TESTS_SHOWN)
    more = tests.size - shown.size
    "#{shown.join(", ")}#{" (+#{more} more)" if more.positive?}"
  end
end
