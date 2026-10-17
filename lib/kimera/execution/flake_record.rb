# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::FlakeRecord
  Flake =
    Data.define(:test, :failed_runs, :seeds, :failure) do
      def to_h = super.transform_keys(&:to_s)
    end

  LOST = { timeout: "timed out (--hard-timeout)" }.freeze
  CRASH = "its worker died"

  def initialize(tests, seeds)
    @tests = tests
    @seeds = seeds
    @failures = Hash.new { |failures, test| failures[test] = [] }
  end

  def note(message, seed)
    @failures[message["id"]] << [seed, message["failure"].to_s] unless message["passed"]
  end

  def lose(test, reason, seed) = @failures[test] << [seed, LOST.fetch(reason, CRASH)]

  def flaky = @failures.keys

  def to_h = { "runs" => @seeds.size, "seeds" => @seeds, "tests" => @tests.size, "flaky" => flakes }

  private

  def flakes
    @failures.map { |test, runs| Flake.new(test, runs.size, runs.map(&:first), runs.first.last).to_h }
  end
end
