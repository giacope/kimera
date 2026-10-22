# frozen_string_literal: true

RSpec.describe("kimera run --max-survivors (threshold gating)") do
  # The sample's 6 uncovered mutants gate on their own unless left unscored.
  it "passes when survivors are within the threshold" do
    run = test_outcome(cwd: test_sample, arguments: ["--max-survivors", "5", "--no-count-no-coverage"])
    expect([run.counts["survived"], run.status]).to(eq([5, 0]), run.output)
  end

  it "fails when they exceed it" do
    expect(test_outcome(cwd: test_sample, arguments: ["--max-survivors", "2"]).status).to(eq(2))
  end
end
