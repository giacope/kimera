# frozen_string_literal: true

require "kimera/registry/self_link"
require "kimera/registry/builder"

using PointFields

RSpec.describe(Kimera::SelfLink) do
  def verdicts(source)
    operators = Kimera::Operators.build(keys: %w[method_unwrap selector_swap])
    points = Kimera::RegistryScan.new(operators: operators).source(source, file: "x.rb").to_a
    points.to_h { |point| [point.original_source, point.safe? ? :warm : point.reasons(Kimera::Reason.unsafety).first] }
  end

  def reasons(source, first, last) = described_class.new(source).ranges.flat_map { it.reasons(first, last) }

  it "sends a call on a literal self to reload where it is another call's receiver", :aggregate_failures do
    expect(verdicts("def m = self.to_s.upcase\n"))
      .to(eq("self.to_s.upcase" => :warm, "self.to_s" => described_class::PRIVILEGE))
    expect(verdicts("def m = self.to_s.count += 1\n")).to(eq("self.to_s" => described_class::PRIVILEGE))
  end

  it "runs warm a call that would leave no bare self, or leaves it where no call follows", :aggregate_failures do
    expect(verdicts("def m = name.to_s.upcase\n").values).to(eq(%i[warm warm]))
    expect(verdicts("def m = self.first(2).to_s\n").values).to(eq(%i[warm warm]))
    expect(verdicts("def m = [self.to_s, to_s.strip]\n").values).to(eq(%i[warm warm]))
  end

  it "taints the link from its first byte to its last, and nothing around it", :aggregate_failures do
    expect(reasons("x = self.to_s.upcase\n", 4, 13)).to(eq([described_class::PRIVILEGE]))
    expect([reasons("x = self.to_s.upcase\n", 3, 13), reasons("x = self.to_s.upcase\n", 4, 14)]).to(eq([[], []]))
  end

  it "leaves a link with arguments or a block alone, since no operator unwraps it", :aggregate_failures do
    expect(described_class.new("self.to_s(2).upcase\nself.sort { 1 }.first\n").ranges).to(eq([]))
    expect(described_class.new("def self.build = new\nself.class\n").ranges).to(eq([]))
  end

  it "finds nothing in source that does not parse" do
    expect(described_class.new("x = self.to_s.upcase\ndef m(\n").ranges).to(eq([]))
  end
end
