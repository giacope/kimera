require_relative "../lib/money"

RSpec.describe "a euro deployment" do
  it "formats euros once configured" do
    Money::OPTIONS[:currency] = "EUR"
    expect(Money.format(250)).to eq("2.50 EUR")
  end
end
