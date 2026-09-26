# frozen_string_literal: true

RSpec.describe("coverage-driven selection") do
  # The Pricing service's 6 mutants have no spec.
  it "marks untouched mutants as no_coverage instead of running the whole suite", :aggregate_failures do
    test_run(cwd: test_sample) do |output, report, _status|
      expect(report).not_to(be_nil, "no report; output:\n#{output}")
      expect(report["counts"]).to(include("no_coverage" => 6, "survived" => 5))
      expect(report["mutation_score"]).to(be_within(0.001).of(17.0 / 22.0))
    end
  end

  it "without coverage, untouched mutants run against everything and survive", :aggregate_failures do
    test_run(cwd: test_sample, args: ["--no-coverage"]) do |output, report, _status|
      expect(report).not_to(be_nil, "no report; output:\n#{output}")
      # The 6 uncovered mutants join the 5 survivors.
      expect(report["counts"]).to(include("no_coverage" => 0, "survived" => 11))
    end
  end
end
