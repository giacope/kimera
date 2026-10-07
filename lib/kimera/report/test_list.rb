# frozen_string_literal: true

require_relative "../support/readout"

module Kimera
  module Report
  end
end

class Kimera::Report::TestList
  SHOWN = 3

  def initialize(report, path)
    @report = report
    @path = path
  end

  def lines(result)
    tests = Array(result.covering_tests)
    count = tests.size
    return [] if count.zero?
    listed = tests.first(SHOWN).map { |test| "  #{named(test)}" }
    ["covered by #{count} test(s):", *listed, *more(result, count - SHOWN)]
  end

  private

  def named(test) = Kimera::Readout.label(test, @report.test(test))

  def more(result, hidden)
    return [] unless hidden.positive?
    ["  (+#{hidden} more#{"; all of them: kimera mutant #{result.mutant_id} --report #{@path}" if @path})"]
  end
end
