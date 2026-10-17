# frozen_string_literal: true

require_relative "fixtures"

RSpec.describe Catalog do
  # Parsed once for the whole group; examples share (and may change) it.
  before(:all) do
    Catalog::Item.default_stock = 5
    @catalog = Catalog.load(EXPORT)
  end

  it "loads every data row" do
    expect(@catalog.size).to be >= 5
  end

  it "parses prices with either decimal mark and a currency sign" do
    expect(@catalog["TEA-001"].price_cents).to eq(750)
    expect(@catalog["TEA-002"].price_cents).to eq(625)
    expect(@catalog["TEA-003"].price_cents).to eq(2_400)
    expect(@catalog["CUP-010"].price).to eq("3.05")
  end

  it "normalises and de-duplicates tags" do
    expect(@catalog["TEA-001"].tags).to eq(%w[green japan])
  end

  it "fills a blank stock with the default in force at load time" do
    expect(@catalog["TEA-003"].stock).to eq(5)
    expect(@catalog["TEA-002"]).not_to be_in_stock
  end

  it "finds items by tag" do
    expect(@catalog.tagged("japan")).to eq(%w[POT-100 TEA-001 TEA-003])
  end

  it "filters by an inclusive price range, cheapest first" do
    expect(@catalog.in_price_range(305, 750)).to eq(%w[CUP-010 TEA-002 TEA-001])
  end

  it "restocks" do
    before = @catalog["POT-100"].stock
    @catalog.restock("POT-100", 3)
    expect(@catalog["POT-100"].stock).to eq(before + 3)
    expect { @catalog.restock("POT-100", 0) }.to raise_error(ArgumentError)
  end

  it "accepts new items but not duplicate skus" do
    @catalog.add(Catalog::Item.new(sku: "MUG-001", name: "Mug", price_cents: 900))
    expect { @catalog.add(Catalog::Item.new(sku: "TEA-001", name: "x", price_cents: 1)) }
      .to raise_error(ArgumentError, /duplicate sku TEA-001/)
  end
end
