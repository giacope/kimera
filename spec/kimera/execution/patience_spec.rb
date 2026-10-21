# frozen_string_literal: true

require "kimera/execution/patience"

# A test may run for the configured soft timeout, or for its own baseline
# × 3 + 1s when that is longer, capped by the hard watchdog's ceiling.
RSpec.describe(Kimera::Execution::Patience) do
  let(:timings) { { "fast" => 0.1, "slow" => 4.7 } }

  it "keeps the configured limit for a test the baseline ran fast or never timed", :aggregate_failures do
    patience = described_class.new(5.0, timings: timings)
    expect([patience.limit("fast"), patience.limit("unknown")]).to(eq([5.0, 5.0]))
  end

  it "raises the limit for a test whose baseline needs more" do
    expect(described_class.new(5.0, timings: timings).limit("slow")).to(be_within(1e-9).of(15.1))
  end

  it "caps the raise at the ceiling but never lowers the configured limit", :aggregate_failures do
    expect(described_class.new(5.0, timings: timings, ceiling: 12.0).limit("slow")).to(eq(12.0))
    expect(described_class.new(5.0, timings: timings, ceiling: 3.0).limit("slow")).to(eq(5.0))
  end

  it "has no limit without a configured one" do
    expect(described_class.new(nil, timings: timings).limit("slow")).to(be_nil)
  end

  it "gives a set of tests the longest of their limits", :aggregate_failures do
    patience = described_class.new(5.0, timings: timings)
    expect(patience.longest(%w[fast slow])).to(be_within(1e-9).of(15.1))
    expect(patience.longest([])).to(eq(5.0))
  end
end
