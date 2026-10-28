# frozen_string_literal: true

require_relative "../rewrite/mutant_text"
require_relative "coloring"
require_relative "screen"
require_relative "sections"
require_relative "../support/snippet"
require_relative "test_health"
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
  include Kimera::Report::TestHealth

  def initialize(registry, io: $stdout, color: nil)
    @registry = registry
    @io = io
    @color = color
  end

  COVERAGE_SECTIONS = { hint: :hint, list: :missing }.freeze

  def report(report, scope: nil, coverage: :hint, path: nil)
    header(report, scope)
    survivors(report, Kimera::Report::TestList.new(report, path))
    footer(report, coverage, path, narrowed: !scope.nil?)
  end

  private

  def header(report, scope)
    @io.puts(scope) if scope
    @io.puts(summary(report))
    Kimera::Report::FileTable.new(io: @io).show(report)
  end

  def footer(report, coverage, path, narrowed:)
    __send__(COVERAGE_SECTIONS.fetch(coverage), report, path, narrowed: narrowed)
    regions(report.unmutated)
    leaks(report.leaks)
    flaky(report)
    quality(report)
    Kimera::Report::Actions.new(io: @io).show(report, path: path)
  end

  def survivors(report, tests)
    section("Surviving mutants", report.survived) { |result| survivor(result, tests) }
    section("Reached only by other units' tests", report.unattributed) { |result| unowned(result, tests) }
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

  def survivor(result, tests)
    resolved(result) { |_id, mutant, point| display(mutant, point, result, tests.lines(result)) }
  end

  def unowned(result, tests)
    survivor(result, tests)
    @io.puts("    #{result.detail}")
  end

  def display(mutant, point, result, covering)
    @io.puts
    spotted(result.status.to_s, result.mutant_id, mutant, point)
    diff(point, mutant)
    covering.each { |line| @io.puts("    #{line}") }
    annotate(result)
  end

  def resolved(result)
    id = result.mutant_id
    pair = @registry.point(id)
    yield(id, *pair) if pair
  end

  def diff(point, mutant)
    variant = Kimera::Rewrite::MutantText.new(point, mutant, root: @registry.root).text
    source(red("-"), point.original_source)
    source(green("+"), variant || Kimera::Rewrite::MutantText::UNWRITTEN)
  end

  def source(sign, text) = @io.puts(Kimera::Snippet.new(sign, text).lines("    "))
end
