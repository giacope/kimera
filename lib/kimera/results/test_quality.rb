# frozen_string_literal: true

require_relative "result"

module Kimera
end

class Kimera::TestQuality
  class Standing
    def initialize(covers, kills, unique)
      @covers = covers
      @kills = kills
      @unique = unique
    end

    def to_h = { "covers" => @covers, "kills" => @kills, "unique" => @unique }

    def redundant? = @kills.positive? && @unique.zero?

    def idle? = @kills.zero?

    def covering? = @covers.positive?
  end

  def initialize(results, suite)
    @results = results
    @suite = suite
  end

  def to_h
    standings = rank
    { "tests" => @suite.size, "kills_nothing" => standings.select { |_test, standing| standing.idle? }.keys }
      .merge("redundant" => standings.select { |_test, standing| standing.redundant? }.keys)
      .merge("covers_nothing" => @suite - standings.keys, "standings" => standings.transform_values(&:to_h))
  end

  private

  def rank
    covers, kills, unique = tallies(@results.select { |result| result.covered? && !result.status?(:uncovered_by_unit) })
    @suite.to_h { |test| [test, Standing.new(covers[test], kills[test], unique[test])] }
      .select { |_test, standing| standing.covering? }
  end

  def tallies(judged)
    rows = judged.map(&:to_h)
    found = rows.map { |row| Array(row["killing_tests"] || row["failing_tests"]).uniq }
    [rows.flat_map { |row| Array(row["covering_tests"]) }, found.flatten, found.select(&:one?).flatten]
      .map { |tests| tally(tests) }
  end

  def tally(tests) = Hash.new(0).merge(tests.tally)
end
