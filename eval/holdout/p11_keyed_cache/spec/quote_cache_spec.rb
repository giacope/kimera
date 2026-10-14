require_relative "../lib/quote_cache"

RSpec.describe QuoteCache do
  it "charges the base up to 2kg" do
    expect(QuoteCache.quote(1, :domestic)).to eq(500)
    expect(QuoteCache.quote(2, :domestic)).to eq(500)
    expect(QuoteCache.quote(3, :domestic)).to eq(700)
  end

  it "charges more internationally" do
    expect(QuoteCache.quote(3, :intl)).to eq(1700)
  end

  it "discounts heavy parcels" do
    expect(QuoteCache.quote(20, :domestic)).to eq(3690)
    expect(QuoteCache.quote(19, :domestic)).to eq(3900)
  end

  it "re-reads a key cached by an earlier example" do
    expect(QuoteCache.quote(3, :domestic)).to eq(700)
  end
end
