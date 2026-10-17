# frozen_string_literal: true

require_relative "result"

module Kimera
end

class Kimera::TestQuality
  Standing =
    Data.define(:covers, :kills, :unique) do
      def to_h = super.transform_keys(&:to_s)

      def redundant? = kills.positive? && unique.zero?
    end

  def initialize(results, suite)
    @results = results
    @suite = suite
  end

  def to_h
    standings = rank
    { "tests" => @suite.size, "kills_nothing" => standings.select { |_test, standing| standing.kills.zero? }.keys }
      .merge("redundant" => standings.select { |_test, standing| standing.redundant? }.keys)
      .merge("covers_nothing" => @suite - standings.keys, "standings" => standings.transform_values(&:to_h))
  end

  private

  def rank
    covers, kills, unique = tallies(@results.select { |result| result.covered? && result.status != :uncovered_by_unit })
    @suite.filter_map { |test| [test, Standing.new(covers[test], kills[test], unique[test])] if covers[test].positive? }
      .to_h
  end

  def tallies(judged)
    found = judged.map { |result| Array(result.killing_tests || result.failing_tests).uniq }
    [judged.flat_map { |result| Array(result.covering_tests) }, found.flatten, found.select(&:one?).flatten]
      .map { |tests| tally(tests) }
  end

  def tally(tests) = Hash.new(0).merge(tests.tally)
end
