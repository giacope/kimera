# frozen_string_literal: true

RSpec.describe("kimera run (end-to-end)") do
  def test_counts
    {
      "total" => 28, "killed" => (be >= 8), "survived" => (be >= 1),
      "timeout" => 0, "error" => 0, "leaks" => 0
    }
  end

  it "produces correct killed/survived results with no leaks, timeouts, or errors", :aggregate_failures do
    test_run(cwd: test_sample) do |output, report, status|
      expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
      expect(report["counts"]).to(include(test_counts))
      expect([report["mutation_score"], status]).to(match([(be > 0.4), 2]))
    end
  end

  it "reports the known boundary survivor `order_total <= 0`" do
    test_run(cwd: test_sample) do |_output, report, _status|
      survivors = report["results"].select { |r| r["status"] == "survived" }
      expect(survivors.map { |r| r["mutant_id"] }).to(include(3))
    end
  end
end
