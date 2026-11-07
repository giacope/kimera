# frozen_string_literal: true

require_relative "../support/readout"

module Kimera
  module Report
  end
end

class Kimera::Report::TestList
  SHOWN = 3

  def initialize(notes, saved)
    @notes = notes
    @saved = saved
  end

  def lines(result)
    tests = Array(result.to_h["covering_tests"])
    count = tests.size
    return [] if count.zero?
    listed = tests.first(SHOWN).map { |test| "  #{named(test)}" }
    ["covered by #{count} test(s):", *listed, *more(result, count - SHOWN)]
  end

  private

  def named(test) = Kimera::Readout::Label.new(test, @notes.test(test)).text

  def more(result, hidden)
    return [] unless hidden.positive?
    ["  (+#{hidden} more#{@saved.more(result.to_h["mutant_id"])})"]
  end
end
