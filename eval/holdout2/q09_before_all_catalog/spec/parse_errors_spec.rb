# frozen_string_literal: true

RSpec.describe "Catalog parse errors" do
  it "rejects a malformed sku with its line number" do
    expect { Catalog.load("\nTEA-1 | x | 1 | | 1\n") }.to raise_error(Catalog::ParseError, /line 2: bad sku/)
  end

  it "rejects a missing name" do
    expect { Catalog.load("TEA-001 |  | 1 | | 1") }.to raise_error(Catalog::ParseError, /missing name/)
  end

  it "rejects prices with three decimals" do
    expect { Catalog.load("TEA-001 | x | 1.005 | | 1") }.to raise_error(Catalog::ParseError, /too many decimals/)
  end
end
