# frozen_string_literal: true

require "kimera/support/seed"

RSpec.describe(Kimera::Seed) do
  it "derives one seed per test from the run's seed, the same each time", :aggregate_failures do
    expect(Array.new(2) { described_class.derive(7, "a") }.uniq.size).to(eq(1))
    expect(described_class.derive(7, "a")).to(eq((7 ^ Zlib.crc32("a")) % (2**31)))
    expect(
      [
        described_class.derive(7, "b"),
        described_class.derive(8, "a")
      ]
    ).not_to(include(described_class.derive(7, "a")))
    expect(described_class.derive((2**31) - 1, "zz")).to(be_between(0, (2**31) - 1))
  end
end
