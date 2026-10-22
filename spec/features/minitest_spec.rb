# frozen_string_literal: true

RSpec.describe("kimera run with the Minitest adapter") do
  def minitest
    File.join(test_repository_root, "examples", "minitest_app")
  end

  it "drives a Minitest suite, killing caught mutants and reporting the survivor", :aggregate_failures do
    run = test_outcome(cwd: minitest, tests: "test/**/*_test.rb", arguments: ["--framework", "minitest"])
    expect(run.counts.slice("total", "killed", "survived", "error", "timeout", "no_coverage")).to(
      eq("total" => 15, "killed" => 14, "survived" => 1, "error" => 0, "timeout" => 0, "no_coverage" => 0), run.output
    )
    expect([run.verdicts.key("survived"), run.status]).to(eq([14, 2]))
  end
end
