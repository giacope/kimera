require_relative "../lib/pricing"

RSpec.describe Pricing do
  it "discounts gold and silver" do
    expect(Pricing.price(100, :gold)).to eq(85)
    expect(Pricing.price(100, :silver)).to eq(90)
  end

  it "discounts bronze and leaves unknown tiers alone" do
    expect(Pricing.price(200, :bronze)).to eq(190)
    expect(Pricing.price(100, :none)).to eq(100)
  end

  it "never goes below the floor" do
    expect(Pricing.price(11, :gold)).to eq(10)
    expect(Pricing.price(10, :none)).to eq(10)
    expect(Pricing.price(9, :none)).to eq(10)
  end

  it "hits the same cache key again" do
    expect(Pricing.price(100, :gold)).to eq(85)
  end

  it "knows bulk bounds" do
    expect(Pricing.bulk?(20)).to be(true)
    expect(Pricing.bulk?(19)).to be(false)
    expect(Pricing.bulk?(500)).to be(true)
    expect(Pricing.bulk?(501)).to be(false)
  end
end
