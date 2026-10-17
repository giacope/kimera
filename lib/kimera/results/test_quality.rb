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
    covers, kills, unique = counts
    @suite.filter_map { |test| [test, Standing.new(covers[test], kills[test], unique[test])] if covers[test].positive? }
      .to_h
  end

  def counts
    tallies = Array.new(3) { Hash.new(0) }
    @results.each { |result| count(result, *tallies) if result.covered? && result.status != :uncovered_by_unit }
    tallies
  end

  def count(result, covers, kills, unique)
    found = Array(result.killing_tests || result.failing_tests).uniq
    Array(result.covering_tests).uniq.each { |test| covers[test] += 1 }
    found.each { |test| kills[test] += 1 }
    unique[found.first] += 1 if found.one?
  end
end
