# frozen_string_literal: true

require "kimera/listing"

RSpec.describe(Kimera::Listing) do
  it "lists a few items, one per line" do
    expect(described_class.new(%w[a b]).lines("  ")).to(eq("\n  a\n  b"))
  end

  it "lists up to ten items, then how many more", :aggregate_failures do
    ten = (1..10).map(&:to_s)
    listed = ten.map { |item| "\n #{item}" }.join
    expect(described_class.new(ten).lines(" ")).to(eq(listed))
    expect(described_class.new([*ten, "11", "12"]).lines(" ")).to(eq("#{listed}\n … and 2 more"))
  end

  it "lists nothing for no items" do
    expect(described_class.new([]).lines(" ")).to(eq(""))
  end
end
