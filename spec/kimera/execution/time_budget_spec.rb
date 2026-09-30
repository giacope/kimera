# frozen_string_literal: true

require "kimera/execution/time_budget"

# A covering test's relative budget is its baseline time × factor + slack.
RSpec.describe(Kimera::Execution::TimeBudget) do
  it "defaults to ten times the baseline plus a second", :aggregate_failures do
    budget = described_class.new({ "t1" => 0.5 })
    expect(budget.exceeded?("t1", 6.0)).to(be(false))
    expect(budget.exceeded?("t1", 6.01)).to(be(true))
  end

  it "takes its factor and slack from the caller", :aggregate_failures do
    budget = described_class.new({ "t1" => 0.5 }, factor: 2.0, slack: 0.25)
    expect(budget.exceeded?("t1", 1.25)).to(be(false))
    expect(budget.exceeded?("t1", 1.26)).to(be(true))
  end

  it "never charges a test it has no baseline for" do
    expect(described_class.new({ "t1" => 0.0 }).exceeded?("t2", 1e9)).to(be(false))
  end

  it "has no baselines at all when none were measured" do
    expect(described_class::NONE.exceeded?("t1", 1e9)).to(be(false))
  end

  it "explains a verdict with the runs, the budget and how it was set" do
    budget = described_class.new({ "t1" => 0.0351 }, factor: 10.0, slack: 1.0)
    expect(budget.explain("t1", [2.0412, 2.0391], 0.0364)).to(
      eq(
        "t1 ran past its relative time budget with the mutant on (2.04s, then 2.04s; budget 1.35s = " \
          "baseline 0.035s × 10.0 + 1.0s), and in 0.036s with it off"
      )
    )
  end
end
