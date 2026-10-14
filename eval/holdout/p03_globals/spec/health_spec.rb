require_relative "../lib/health"

RSpec.describe Health do
  it "is ok below warn" do
    expect(Health.level(69)).to eq(:ok)
    expect(Health.level(0)).to eq(:ok)
  end

  it "warns from 70" do
    expect(Health.level(70)).to eq(:warning)
    expect(Health.level(89)).to eq(:warning)
  end

  it "is critical from 90" do
    expect(Health.level(90)).to eq(:critical)
  end

  it "alerts on two non-ok values" do
    expect(Health.alert?([70, 90, 1])).to be(true)
    expect(Health.alert?([70, 1, 1])).to be(false)
  end
end
