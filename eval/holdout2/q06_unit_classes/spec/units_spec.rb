# frozen_string_literal: true

RSpec.describe Units do
  it "names every generated class" do
    expect(Units::Foot.name).to eq("Units::Foot")
    expect(Units::Foot.superclass).to eq(Units::Quantity)
  end

  it "derives factors from the table" do
    expect(Units::Foot.factor).to eq(Rational("304.8"))
    expect(Units::Mile.factor).to eq(Rational("1609344"))
    expect(Units::Ounce.factor).to eq(Rational("28.349523125"))
    expect(Units::Stone.factor).to eq(Rational("6350.29318"))
  end

  it "lists units of a dimension smallest first" do
    expect(described_class.units_for(:length)).to eq(%w[mm cm in ft m km mi])
    expect(described_class.units_for(:mass)).to eq(%w[g oz lb kg st])
  end

  describe ".parse" do
    it "reads integers and decimals" do
      expect(described_class.parse("12 km").to_s).to eq("12 km")
      expect(described_class.parse(" 2.5 lb ").value).to eq(Rational(5, 2))
      expect(described_class.parse("-3 m").value).to eq(-3)
    end

    it "rejects unknown units and junk" do
      expect { described_class.parse("3 parsecs") }.to raise_error(ArgumentError, /unknown unit parsecs/)
      expect { described_class.parse("km 3") }.to raise_error(ArgumentError, /cannot parse/)
    end
  end
end
