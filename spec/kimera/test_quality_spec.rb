# frozen_string_literal: true

require "kimera/results/test_quality"

RSpec.describe(Kimera::TestQuality, :aggregate_failures) do
  def result(id, status, cover, kills = nil, failing: nil)
    Kimera::MutantResult.new(
      mutant_id: id, status: status, file: "x.rb", covering_tests: cover, killing_tests: kills, failing_tests: failing
    )
  end

  let(:results) do
    [
      result(1, :killed, %w[a b c], %w[a b]), result(2, :killed, %w[a c], %w[a]),
      result(3, :survived, %w[c d]), result(4, :timeout, %w[b], failing: nil),
      result(5, :killed, %w[b e], failing: %w[e]), result(6, :uncovered_by_unit, %w[f]),
      result(7, :no_coverage, nil), result(8, :killed, %w[b], %w[b b])
    ]
  end
  let(:quality) { described_class.new(results, %w[a b c d e f g]).to_h }

  it "ranks each test that covers a judged mutant by what it covers, kills, and alone kills" do
    expect(quality.fetch("standings")).to(
      eq(
        "a" => { "covers" => 2, "kills" => 2, "unique" => 1 }, "b" => { "covers" => 4, "kills" => 2, "unique" => 1 },
        "c" => { "covers" => 3, "kills" => 0, "unique" => 0 }, "d" => { "covers" => 1, "kills" => 0, "unique" => 0 },
        "e" => { "covers" => 1, "kills" => 1, "unique" => 1 }
      )
    )
  end

  it "names the tests that kill nothing they cover, the redundant ones, and those that cover nothing" do
    expect(quality.values_at("tests", "kills_nothing", "covers_nothing")).to(eq([7, %w[c d], %w[f g]]))
    redundant = described_class.new(results.first(1) + [result(9, :killed, %w[a b], %w[b])], %w[a b]).to_h
    expect([quality.fetch("redundant"), redundant.fetch("redundant")]).to(eq([[], ["a"]]))
  end
end
