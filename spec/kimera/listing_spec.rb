# frozen_string_literal: true

require "kimera/listing"

RSpec.describe(Kimera::Listing) do
  it "lists up to ten items, one per line, then how many more", :aggregate_failures do
    expect(described_class.lines(%w[a b], "  ")).to(eq("\n  a\n  b"))
    ten = (1..10).map(&:to_s)
    listed = ten.map { |item| "\n #{item}" }.join
    expect(described_class.lines(ten, " ")).to(eq(listed))
    expect(described_class.lines([*ten, "11", "12"], " ")).to(eq("#{listed}\n … and 2 more"))
    expect(described_class.lines([], " ")).to(eq(""))
  end
end
