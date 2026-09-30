# frozen_string_literal: true

module Kimera
  module Report
  end
end

module Kimera::Report::Sections
  private

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
    @io.puts("  #{red("unjudged")} ##{id}  #{where(@registry.index[id], result)}  #{result.detail}")
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

  def where(point, result)
    point ? "#{point.file}:#{point.location.start_line}" : result.file.to_s
  end

  def hint(report, path)
    count = report.uncovered.size
    return if count.zero?
    @io.puts
    @io.puts("#{count} mutant(s) have no covering test; #{command(path)}")
  end

  def command(path)
    return "list them with: kimera report #{path} --status no_coverage" if path
    "re-run with --report FILE, then `kimera report FILE --status no_coverage` to list them"
  end

  def missing(report, _path = nil) = section("Mutants with no covering test", report.uncovered) { |r| uncovered(r) }

  def uncovered(result)
    resolved(result) { |id, mutant, point| spotted("no coverage", id, mutant, point) }
  end

  def spotted(status, id, mutant, point)
    @io.puts("  #{yellow(status)} ##{id}  #{point.file}:#{point.location.start_line}  [#{mutant.label}]")
  end

  def leaks(leaks)
    return if leaks.empty?
    @io.puts
    @io.puts(yellow("State-leak warnings (#{leaks.size}):"))
    leaks.each { |leak| @io.puts("  - ##{leak.mutant_id}  #{leak.detail}") }
  end
end
