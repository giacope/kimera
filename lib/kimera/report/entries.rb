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
    section("Surviving mutants", having(report, :survived)) { |result| survivor(result, tests) }
    section("Reached only by other units' tests", having(report, :uncovered_by_unit)) { |r| unowned(r, tests) }
  end

  def unjudged(report) = section("Mutants Kimera could not judge", having(report, :harness_error)) { |r| unjudge(r) }

  def hint(report, saved, narrowed:)
    count = report.count { |result| result.status?(:no_coverage) }
    return if count.zero?
    @io.puts
    @io.puts("#{count} mutant(s) #{narrowed ? NARROWED : "have no covering test"}; #{saved.listing}")
  end

  def missing(report, _saved, narrowed:)
    title = narrowed ? "Mutants #{NARROWED}" : "Mutants with no covering test"
    section(title, having(report, :no_coverage)) { |result| uncovered(result) }
  end

  private

  def having(report, status) = report.select { |result| result.status?(status) }

  def section(title, results, &)
    listed = results.sort
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
    @io.puts("    #{result.to_h["detail"]}")
  end

  def display(mutant, point, result, covering)
    @io.puts
    row = result.to_h
    spotted(row["status"], row["mutant_id"], mutant, point)
    diff(point, mutant)
    covering.each { |line| @io.puts("    #{line}") }
    annotate(result)
  end

  def resolved(result)
    id = result.to_h["mutant_id"]
    pair = @registry[id] { return }
    yield(id, *pair)
  end

  def diff(point, mutant)
    variants = @registry.texts(point, mutant, Kimera::Rewrite::MutantText)
    source(@palette.red("-"), point.original_source)
    source(@palette.green("+"), Kimera::MutatedText.new(variants).to_s)
  end

  def source(sign, text) = @io.puts(Kimera::Readout.new(text).quoted(sign, "    "))

  def unjudge(result)
    row = result.to_h
    id = row["mutant_id"]
    @io.puts("  #{@palette.red("unjudged")} ##{id}  #{where(@registry.index[id], row)}")
    Kimera::Readout.new(row["detail"]).lines.each { |line| @io.puts("    #{line}") }
    annotate(result)
  end

  def annotate(result) = remark(result, "note", "note: ")

  def remark(result, key, label)
    text = result.to_h[key]
    @io.puts("    #{label}#{text}") if text
  end

  def where(point, row) = point ? place(point) : row["file"].to_s

  def place(point)
    location = point.location
    method = point.method_name
    "#{point.file}:#{location}#{"  in #{method}" if method}"
  end

  def uncovered(result)
    resolved(result) { |id, mutant, point| spotted("no coverage", id, mutant, point) }
    remark(result, "detail", "")
  end

  def spotted(status, id, mutant, point)
    @io.puts("  #{@palette.yellow(status)} ##{id}  #{place(point)}  [#{mutant}]")
  end
end
