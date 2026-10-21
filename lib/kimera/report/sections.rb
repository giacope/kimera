# frozen_string_literal: true

require_relative "../support/readout"

module Kimera
  module Report
  end
end

module Kimera::Report::Sections
  NARROWED = "not covered by the narrowed tests"

  private

  def regions(found) = listing(bold("Not mutated (#{found.size} region(s)):"), found)

  def listing(heading, rows)
    return if rows.empty?
    @io.puts
    @io.puts(heading)
    rows.each { |row| @io.puts("  #{row.line}") }
  end

  def unjudged(report) = section("Mutants Kimera could not judge", report.errors) { |r| unjudge(r) }

  def waivers(report)
    judged = report.statuses(:ignored).select(&:verdict)
    return if judged.empty?
    @io.puts
    @io.puts(verdicts(judged))
  end

  def verdicts(judged)
    lapsed = judged.count(&:lapsed?)
    surviving = judged.count { |result| result.verdict == :survived }
    other = judged.size - lapsed - surviving
    line = "#{lapsed} ignored mutant(s) are now killed (their entries can be pruned); #{surviving} still survive"
    other.zero? ? "#{line}." : "#{line}; #{other} could not be judged."
  end

  def unjudge(result)
    id = result.mutant_id
    @io.puts("  #{red("unjudged")} ##{id}  #{where(@registry.index[id], result)}")
    Kimera::Readout.new(result.detail).lines.each { |line| @io.puts("    #{line}") }
    annotate(result)
  end

  def annotate(result)
    note = result.note
    @io.puts("    note: #{note}") if note
  end

  def rejudged(report)
    judged = report.results.select(&:note)
    return if judged.empty?
    @io.puts
    @io.puts("#{judged.size} mutant(s) the warm pass could not judge, judged again in fresh mirrors: #{tally(judged)}.")
  end

  def tally(judged)
    judged.group_by(&:status).map { |status, results| "#{results.size} #{named(status)}" }.join(", ")
  end

  def named(status) = status == :harness_error ? "unjudged" : status

  def where(point, result) = point ? place(point) : result.file.to_s

  def place(point)
    location = point.location
    method = point.method_name
    "#{point.file}:#{location.start_line}:#{location.start_column + 1}#{"  in #{method}" if method}"
  end

  def hint(report, path, narrowed: false)
    count = report.uncovered.size
    return if count.zero?
    @io.puts
    @io.puts("#{count} mutant(s) #{narrowed ? NARROWED : "have no covering test"}; #{command(path)}")
  end

  def command(path)
    return "list them with: kimera report #{path} --status no_coverage" if path
    "run without --no-report, then `kimera report --status no_coverage` to list them"
  end

  def missing(report, _path = nil, narrowed: false)
    title = narrowed ? "Mutants #{NARROWED}" : "Mutants with no covering test"
    section(title, report.uncovered) { |result| uncovered(result) }
  end

  def uncovered(result)
    resolved(result) { |id, mutant, point| spotted("no coverage", id, mutant, point) }
    reason = result.detail
    @io.puts("    #{reason}") if reason
  end

  def spotted(status, id, mutant, point)
    @io.puts("  #{yellow(status)} ##{id}  #{place(point)}  [#{mutant.label}]")
  end

  def leaks(leaks) = listing(yellow("State-leak warnings (#{leaks.size}):"), leaks)
end
