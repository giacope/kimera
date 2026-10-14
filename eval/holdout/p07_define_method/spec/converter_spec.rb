require_relative "../lib/converter"

RSpec.describe Converter do
  let(:c) { Converter.new }

  it "converts exact multiples to integers" do
    expect(c.to_cm(50)).to eql(5)
    expect(c.to_km(2_000_000)).to eql(2)
    expect(c.to_mm(7)).to eql(7)
  end

  it "converts remainders to rounded floats" do
    expect(c.to_cm(55)).to eql(5.5)
    expect(c.to_m(1500)).to eql(1.5)
    expect(c.to_m(1234)).to eql(1.23)
  end

  it "rejects negatives but accepts zero" do
    expect { c.to_m(-1) }.to raise_error(ArgumentError)
    expect(c.to_m(0)).to eql(0)
  end

  it "classifies short and long" do
    expect(c.short?(99)).to be(true)
    expect(c.short?(100)).to be(false)
    expect(c.long?(10_000)).to be(true)
    expect(c.long?(9_999)).to be(false)
  end
end
