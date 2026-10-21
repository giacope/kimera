# frozen_string_literal: true

RSpec.describe("kimera run --max-survivors (threshold gating)") do
  it "passes when survivors are within the threshold and fails when they exceed it", :aggregate_failures do
    # The sample's 6 uncovered mutants gate on their own unless left unscored.
    test_run(cwd: test_sample, arguments: ["--max-survivors", "5", "--no-count-no-coverage"]) do |_o, report, status|
      expect(report["counts"]["survived"]).to(eq(5))
      expect(status).to(eq(0))
    end

    test_run(cwd: test_sample, arguments: ["--max-survivors", "2"]) do |_o, _report, status|
      expect(status).to(eq(2))
    end
  end
end
