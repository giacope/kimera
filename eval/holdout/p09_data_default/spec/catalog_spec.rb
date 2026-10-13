require_relative "../lib/catalog"

RSpec.describe Catalog do
  it "has a standard box" do
    expect(Catalog.standard.volume).to eq(120)
    expect(Catalog.standard.cube?).to be(false)
    expect(Catalog.standard.to_h).to eq(width: 6, height: 4, depth: 5)
  end

  it "detects cubes" do
    expect(Box.new(3, 3, 3).cube?).to be(true)
    expect(Box.new(3, 3, 4).cube?).to be(false)
    expect(Box.new(3, 4, 4).cube?).to be(false)
  end

  it "checks fit in each dimension" do
    s = Catalog.standard
    expect(Box.new(6, 4, 5).fits_in?(s)).to be(true)
    expect(Box.new(7, 1, 1).fits_in?(s)).to be(false)
    expect(Box.new(1, 5, 1).fits_in?(s)).to be(false)
    expect(Box.new(1, 1, 6).fits_in?(s)).to be(false)
  end
end
