# frozen_string_literal: true

require_relative "../mutated_text"
require_relative "../rewrite/mutant_text"
require_relative "../support/readout"

module Kimera
  module Report
  end
end

class Kimera::Report::Entries
  NARROWED = "not covered by the narrowed tests"

  def initialize(io, registry, palette)
    @io = io
    @registry = registry
    @palette = palette
  end

  def survived(report, tests)
    section("Surviving mutants", report.survived) { |result| survivor(result, tests) }
    section("Reached only by other units' tests", report.unattributed) { |result| unowned(result, tests) }
  end

  def unjudged(report) = section("Mutants Kimera could not judge", report.errors) { |r| unjudge(r) }

  def hint(report, saved, narrowed:)
    count = report.uncovered.size
    return if count.zero?
    @io.puts
    @io.puts("#{count} mutant(s) #{narrowed ? NARROWED : "have no covering test"}; #{saved.listing}")
  end

  def missing(report, _saved, narrowed:)
    title = narrowed ? "Mutants #{NARROWED}" : "Mutants with no covering test"
    section(title, report.uncovered) { |result| uncovered(result) }
  end

  private

  def section(title, results, &)
    listed = results.sort_by(&:mutant_id)
    heading(title, listed.size) unless listed.empty?
    listed.each(&)
  end

  def heading(title, count)
    @io.puts
    @io.puts(@palette.bold("#{title} (#{count}):"))
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
    pair = @registry.point(id) { return }
    yield(id, *pair)
  end

  def diff(point, mutant)
    variants = Kimera::Rewrite::MutantText.new(point, mutant, root: @registry.root).texts
    source(@palette.red("-"), point.original_source)
    source(@palette.green("+"), Kimera::MutatedText.new(variants).to_s)
  end

  def source(sign, text) = @io.puts(Kimera::Readout.new(text).quoted(sign, "    "))

  def unjudge(result)
    id = result.mutant_id
    @io.puts("  #{@palette.red("unjudged")} ##{id}  #{where(@registry.index[id], result)}")
    Kimera::Readout.new(result.detail).lines.each { |line| @io.puts("    #{line}") }
    annotate(result)
  end

  def annotate(result)
    note = result.note
    @io.puts("    note: #{note}") if note
  end

  def where(point, result) = point ? place(point) : result.file.to_s

  def place(point)
    location = point.location
    method = point.method_name
    "#{point.file}:#{location.start_line}:#{location.start_column + 1}#{"  in #{method}" if method}"
  end

  def uncovered(result)
    resolved(result) { |id, mutant, point| spotted("no coverage", id, mutant, point) }
    reason = result.detail
    @io.puts("    #{reason}") if reason
  end

  def spotted(status, id, mutant, point)
    @io.puts("  #{@palette.yellow(status)} ##{id}  #{place(point)}  [#{mutant.label}]")
  end
end
