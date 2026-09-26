# frozen_string_literal: true

RSpec.describe("kimera run with the Minitest adapter") do
  def minitest
    File.join(test_repo_root, "examples", "minitest_app")
  end

  it "drives a Minitest suite, killing caught mutants and reporting the survivor", :aggregate_failures do
    test_run(
      cwd: minitest,
      tests: "test/**/*_test.rb",
      args: ["--framework", "minitest"]
    ) do |output, report, status|
      expect(report).not_to(be_nil, "no report; output:\n#{output}")
      counts = report["counts"]

      expect(counts["total"]).to(eq(15))
      expect(counts["killed"]).to(eq(14))
      expect(counts["survived"]).to(eq(1))
      expect(counts["error"]).to(eq(0))
      expect(counts["timeout"]).to(eq(0))
      expect(counts["no_coverage"]).to(eq(0))

      survivor = report["results"].find { |r| r["status"] == "survived" }
      expect(survivor["mutant_id"]).to(eq(14))
      expect(status).to(eq(2))
    end
  end
end
