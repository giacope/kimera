# frozen_string_literal: true

require "kimera/frameworks/seed"

RSpec.describe(Kimera::Seed) do
  def seed(value) = described_class.new("KIMERA_SEED" => value.to_s)

  it "reads the run's seed from the environment, or none", :aggregate_failures do
    expect([seed(7).given, described_class.new({}).given]).to(eq([[7], []]))
    expect { seed("x").given }.to(raise_error(ArgumentError))
  end

  it "derives one seed per test from the run's seed, the same each time", :aggregate_failures do
    expect(Array.new(2) { seed(7).for("a") }.uniq.size).to(eq(1))
    expect(seed(7).for("a")).to(eq([(7 ^ Zlib.crc32("a")) % (2**31)]))
    expect([seed(7).for("b"), seed(8).for("a")]).not_to(include(seed(7).for("a")))
    expect(seed((2**31) - 1).for("zz")).to(all(be_between(0, (2**31) - 1)))
    expect(described_class.new({}).for("a")).to(eq([]))
  end

  it "reads the process environment by default" do
    seeded(5) { expect(described_class.new.given).to(eq([5])) }
  end
end
