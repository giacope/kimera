require_relative "../lib/registry"

RSpec.describe Registry do
  it "adds the even bonus" do
    expect(Registry.score(10)).to eq(15)
    expect(Registry.score(7)).to eq(7)
  end

  it "applies the big penalty above 100" do
    expect(Registry.score(120)).to eq(160)
    expect(Registry.score(101)).to eq(100)
  end

  it "does not penalise exactly 100" do
    expect(Registry.score(100)).to eq(150)
  end

  it "registers both rules" do
    expect(Registry.table.keys).to eq(%i[even big])
  end
end
