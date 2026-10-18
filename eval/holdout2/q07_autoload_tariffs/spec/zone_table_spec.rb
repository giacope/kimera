# frozen_string_literal: true

RSpec.describe "Shipping::ZoneTable" do
  let(:table) { Shipping::ZoneTable }

  it "maps listed countries to their zones" do
    expect(table.zone_for(" pl ")).to eq(3)
    expect(table.zone_for(:CH)).to eq(4)
  end

  it "puts unlisted countries in zone 6" do
    expect(table.zone_for("BR")).to eq(6)
  end

  it "rejects malformed codes" do
    expect { table.zone_for("DEU") }.to raise_error(Shipping::UnknownDestination)
  end

  it "indexes every listed country exactly once" do
    expect(table::BY_COUNTRY.size).to eq(18)
    expect(table::BY_COUNTRY).to be_frozen
  end
end
