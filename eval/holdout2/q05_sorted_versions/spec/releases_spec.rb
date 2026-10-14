# frozen_string_literal: true

RSpec.describe Releases do
  it "keeps the supported list in precedence order" do
    expect(Releases::SUPPORTED.map(&:to_s)).to eq(%w[
      2.7.8 3.0.6 3.1.4 3.2.0-rc.1 3.2.0-rc.2 3.2.0-rc.10 3.2.0 3.2.2 3.3.0-preview.2 3.3.0 3.10.0-beta
    ])
  end

  it "knows its bounds" do
    expect([Releases::OLDEST.to_s, Releases::NEWEST.to_s]).to eq(["2.7.8", "3.10.0-beta"])
  end

  it "finds the latest stable release" do
    expect(described_class.latest_stable.to_s).to eq("3.3.0")
  end

  describe ".supported?" do
    it "accepts listed versions" do
      expect(described_class.supported?("3.2.0-rc.2")).to be(true)
      expect(described_class.supported?(SemVer.parse("2.7.8"))).to be(true)
    end

    it "rejects versions that are in range but not listed" do
      expect(described_class.supported?("3.1.0")).to be(false)
    end
  end

  it "lists stable upgrades" do
    expect(described_class.upgrades_from("3.1.4")).to eq(%w[3.2.0 3.2.2 3.3.0])
  end

  describe ".pick" do
    it "picks the newest stable within the major" do
      expect(described_class.pick("~> 3.2")).to eq("3.3.0")
      expect(described_class.pick("~> 2.7")).to eq("2.7.8")
    end

    it "returns nil when nothing matches" do
      expect(described_class.pick("~> 4.0")).to be_nil
    end
  end

  it "clamps into the supported range" do
    expect(described_class.clamp("1.9.3")).to eq("2.7.8")
    expect(described_class.clamp("9.0.0")).to eq("3.10.0-beta")
    expect(described_class.clamp("3.0.0")).to eq("3.0.0")
  end
end
