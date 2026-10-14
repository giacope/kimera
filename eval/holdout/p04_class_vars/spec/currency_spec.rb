require_relative "../lib/currency"

RSpec.describe Currency do
  it "converts EUR and USD both ways" do
    expect(Currency.convert(1000, "EUR", "USD")).to eq(1100)
    expect(Currency.convert(1100, "USD", "EUR")).to eq(1000)
  end

  it "converts GBP with rounding" do
    expect(Currency.convert(500, "GBP", "USD")).to eq(625)
    expect(Currency.convert(3, "GBP", "USD")).to eq(4)
  end

  it "is identity for the same currency" do
    expect(Currency.convert(7, "GBP", "GBP")).to eq(7)
  end

  it "shares rates with subclasses" do
    expect(Crypto.convert(1000, "EUR", "USD")).to eq(2200)
    expect(Crypto.rates).to eq("USD" => 100, "EUR" => 110, "GBP" => 125)
  end
end
