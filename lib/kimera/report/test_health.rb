# frozen_string_literal: true

require_relative "../support/readout"

module Kimera
  module Report
  end
end

module Kimera::Report::TestHealth
  SHOWN = 10

  private

  def flaky(report)
    found = report.notes.flaky
    return unless found
    flakes = found.fetch("flaky")
    @io.puts
    rerun = reruns(found)
    @io.puts(flakes.empty? ? "No flaky tests in #{rerun}." : yellow("Flaky tests (#{flakes.size}), in #{rerun}:"))
    flakes.each { |flake| @io.puts("  #{flake_line(report, flake)}") }
    @io.puts("  Each passed the baseline but failed a rerun, so it kills no mutant.") if flakes.any?
  end

  def quality(report)
    suite = report.notes.suite
    return unless suite
    found = report.quality
    idle, redundant = found.values_at("kills_nothing", "redundant")
    @io.puts("", bold("Test quality (#{suite.size} tests):"))
    @io.puts(
      "  #{idle.size} kill none of the mutants they cover; #{redundant.size} are redundant (another test " \
        "kills each mutant they kill); #{found.fetch("covers_nothing").size} cover no mutant in scope."
    )
    { "Kill nothing" => idle, "Redundant" => redundant }.each { |title, tests| listed(report, title, tests) }
  end

  def listed(report, title, tests)
    return if tests.empty?
    @io.puts("  #{title}:")
    tests.first(SHOWN).each { |test| @io.puts("    #{Kimera::Readout.label(test, report.test(test))}") }
    hidden = tests.size - SHOWN
    @io.puts("    (+#{hidden} more; the JSON report's test_quality lists them all)") if hidden.positive?
  end

  def reruns(found)
    "#{found.fetch("runs")} rerun(s) of #{found.fetch("tests")} covering test(s), " \
      "seeds #{found.fetch("seeds").join(", ")}"
  end

  def flake_line(report, flake)
    test = flake.fetch("test")
    reason = Kimera::Readout.lines(flake.fetch("failure")).first || "no message"
    "#{Kimera::Readout.label(test, report.test(test))}  failed #{flake.fetch("failed_runs")} " \
      "(seed #{flake.fetch("seeds").join(", ")}): #{reason}"
  end
end
