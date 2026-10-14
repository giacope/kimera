# frozen_string_literal: true

RSpec.describe Units::Quantity do
  it "converts within a dimension" do
    expect(Units::Mile.new(1).to(Units::Kilometer).round(4)).to eq(1.6093)
    expect(Units::Inch.new(12).to(Units::Foot).value).to eq(1)
    expect(Units::Kilogram.new(1).to(Units::Pound).round(3)).to eq(2.205)
  end

  it "refuses to convert across dimensions" do
    expect { Units::Meter.new(1).to(Units::Gram) }
      .to raise_error(Units::IncompatibleUnits, "cannot convert length to mass")
  end

  it "adds and subtracts in the left operand's unit" do
    sum = Units::Meter.new(1) + Units::Centimeter.new(50)
    expect(sum.to_s).to eq("1.5 m")
    expect((Units::Foot.new(1) - Units::Inch.new(3)).to_s).to eq("0.75 ft")
  end

  it "scales by numbers only" do
    expect((Units::Gram.new(250) * 4).to_s).to eq("1000 g")
    expect { Units::Gram.new(1) * Units::Gram.new(2) }.to raise_error(TypeError)
  end

  it "compares across units of one dimension" do
    expect(Units::Kilometer.new(1)).to be > Units::Mile.new(Rational(1, 2))
    expect(Units::Centimeter.new(100)).to eq(Units::Meter.new(1))
    expect([Units::Foot.new(1), Units::Inch.new(13), Units::Centimeter.new(30)].max.to_s).to eq("13 in")
  end

  it "does not compare across dimensions" do
    expect(Units::Gram.new(1) <=> Units::Meter.new(1)).to be_nil
  end

  it "keeps floats exact enough" do
    expect(Units::Meter.new(0.1).value).to eq(Rational(1, 10))
  end
end
