# frozen_string_literal: true

require_relative "../rewrite/directive"
require_relative "coloring"
require_relative "screen"
require_relative "sections"
require_relative "actions"
require_relative "file_table"
require_relative "../support/readout"
require_relative "test_list"

module Kimera
  module Report
  end
end

class Kimera::Report::Text
  include Kimera::Report::Coloring
  include Kimera::Report::Sections

  def initialize(registry, io: $stdout, color: nil)
    @registry = registry
    @io = io
    @color = color
  end

  COVERAGE_SECTIONS = { hint: :hint, list: :missing }.freeze

  def report(report, scope: nil, coverage: :hint, path: nil)
    @tests = Kimera::Report::TestList.new(report, path)
    header(report, scope)
    survivors(report)
    footer(report, coverage, path)
  end

  private

  def header(report, scope)
    @io.puts(scope) if scope
    @io.puts(summary(report))
    Kimera::Report::FileTable.new(io: @io).show(report)
  end

  def footer(report, coverage, path)
    __send__(COVERAGE_SECTIONS.fetch(coverage), report, path)
    leaks(report.leaks)
    Kimera::Report::Actions.new(io: @io).show(report, path: path)
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

  def covering(result) = @tests.lines(result).each { |line| @io.puts("    #{line}") }
end
