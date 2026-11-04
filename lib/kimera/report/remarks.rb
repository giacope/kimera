# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Remarks
  def initialize(io, palette)
    @io = io
    @palette = palette
  end

  def regions(found) = listing(@palette.bold("Not mutated (#{found.size} region(s)):"), found)

  def leaks(leaks) = listing(@palette.yellow("State-leak warnings (#{leaks.size}):"), leaks)

  def waivers(report)
    judged = report.select { |result| result.status?(:ignored) && result.to_h.key?("verdict") }
    return if judged.empty?
    @io.puts
    @io.puts(verdicts(judged))
  end

  def rejudged(report)
    judged = report.select { |result| result.to_h.key?("note") }
    return if judged.empty?
    @io.puts
    @io.puts("#{judged.size} mutant(s) the warm pass could not judge, judged again in fresh mirrors: #{tally(judged)}.")
  end

  private

  def listing(heading, rows)
    return if rows.empty?
    @io.puts
    @io.puts(heading)
    rows.each { |row| @io.puts("  #{row.line}") }
  end

  def verdicts(judged)
    lapsed = judged.count(&:lapsed?)
    surviving = judged.count { |result| result.to_h["verdict"] == "survived" }
    other = judged.size - lapsed - surviving
    line = "#{lapsed} ignored mutant(s) are now killed (their entries can be pruned); #{surviving} still survive"
    other.zero? ? "#{line}." : "#{line}; #{other} could not be judged."
  end

  def tally(judged)
    judged.group_by { |result| result.to_h["status"] }
      .map { |status, results| "#{results.size} #{named(status)}" }.join(", ")
  end

  def named(status) = status == "harness_error" ? "unjudged" : status
end
