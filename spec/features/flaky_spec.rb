# frozen_string_literal: true

require "kimera/frameworks/seed"

# Two of Coin's tests draw a random number and fail on half the draws. Kimera
# seeds each test from --seed and the test's id, so the seed picked here
# passes the baseline and fails a rerun with another seed.
RSpec.describe("kimera run --flaky-runs (end-to-end)", :aggregate_failures) do
  let(:shaky) { ["./spec/coin_spec.rb[1:1]", "./spec/coin_spec.rb[1:3]"] }

  def heads?(seed, test) = Random.new(Kimera::Seed.new("KIMERA_SEED" => seed.to_s).for(test)).rand(2).zero?

  def seed = (0..).find { |s| shaky.all? { |t| heads?(s, t) && !(heads?(s + 1, t) && heads?(s + 2, t)) } }

  def coin_files
    {
      "app/coin.rb" => "class Coin\n  def heads?(n)\n    n > 0\n  end\n\n  def big?(n)\n    n > 10\n  end\nend\n",
      "spec/coin_spec.rb" => <<~RUBY
        require_relative "../app/coin"

        RSpec.describe Coin do
          it("flips") { expect([Coin.new.heads?(1), rand(2)]).to eq([true, 0]) }
          it("is big past ten") { expect([Coin.new.big?(11), Coin.new.big?(10)]).to eq([true, false]) }
          it("flips big") { expect([Coin.new.big?(11), Coin.new.big?(0), rand(2)]).to eq([true, false, 0]) }
        end
      RUBY
    }
  end

  def coin(arguments) = test_tree(coin_files, "kimera-flaky") { |root| test_outcome(cwd: root, arguments: arguments) }

  def by_method(report)
    report["results"].group_by { |r| r["method"] }.transform_values { |rs| rs.map { |r| r["status"] }.uniq }
  end

  # The flaky-test tally a reseeded run reported.
  def tally(report)
    flaky = report.fetch("flaky_tests")
    {
      counts: flaky.values_at("runs", "seeds", "tests"), tests: flaky.fetch("flaky").map { |f| f["test"] }.sort,
      failures: flaky.fetch("flaky").map { |f| f["failure"] }
    }
  end

  # The verdicts a reseeded run left, and the settings its report records.
  def verdicts_of(report)
    rows = report["results"]
    {
      methods: by_method(report), heads: rows.find { |r| r["method"] == "heads?" }["detail"],
      killers: rows.select { |r| r["method"] == "big?" }.flat_map { |r| r["failing_tests"] }.uniq,
      run: report["run"].slice("seed", "flaky_runs")
    }
  end

  it "reports the tests whose result a reseeded rerun changes, and lets only steady tests kill" do
    run = coin(["--seed", seed.to_s, "--flaky-runs", "2"])
    expect(tally(run.report)).to(
      match(counts: [2, [seed + 1, seed + 2], 3], tests: shaky.sort, failures: all(include("ExpectationNotMetError")))
    )
    expect(verdicts_of(run.report)).to(
      eq(
        methods: { "heads?" => ["no_coverage"], "big?" => ["killed"] },
        heads: "covered only by flaky test(s), which never kill: ./spec/coin_spec.rb[1:1]",
        killers: ["./spec/coin_spec.rb[1:2]"], run: { "seed" => seed, "flaky_runs" => 2 }
      )
    )
    expect(run.output)
      .to(include("Flaky tests (2), in 2 rerun(s) of 3 covering test(s), seeds #{seed + 1}, #{seed + 2}:"))
  end

  # A child that seeded its tests otherwise would see the flaky tests fail in the unmutated mirror.
  it "seeds the isolated tier's tests as the warm path does" do
    run = coin(["--seed", seed.to_s, "--isolated"])
    expect(by_method(run.report).fetch("big?")).to(eq(["killed"]), run.output)
  end

  # The verdicts of a run given only a seed, which keeps no flaky tally and lets the flaky tests kill.
  def seeded_verdicts
    report = coin(["--seed", seed.to_s]).report
    expect(report).not_to(have_key("flaky_tests"))
    expect(by_method(report).fetch("heads?")).to(include("killed"))
    report["results"].map { |r| r.values_at("key", "status", "failing_tests") }
  end

  it "judges the same way twice with one --seed, and lets the flaky tests kill without --flaky-runs" do
    verdicts = Array.new(2) { seeded_verdicts }
    expect([verdicts.uniq.size, verdicts.first.size]).to(eq([1, 4]))
  end
end
