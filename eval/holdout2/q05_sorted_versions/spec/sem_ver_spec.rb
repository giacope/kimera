# frozen_string_literal: true

RSpec.describe SemVer do
  def v(string) = described_class.parse(string)

  it "parses and prints" do
    expect(v(" 1.20.3-alpha.1 ").to_s).to eq("1.20.3-alpha.1")
    expect(v("0.0.1").prerelease?).to be(false)
  end

  it "rejects garbage" do
    expect { v("1.2") }.to raise_error(ArgumentError, /not a version/)
  end

  it "orders by core numbers numerically" do
    expect(v("1.10.0")).to be > v("1.9.9")
    expect(v("2.0.0")).to be > v("1.99.99")
  end

  it "ranks a release above its prereleases" do
    expect(v("1.0.0")).to be > v("1.0.0-rc.1")
    expect(v("1.0.0-rc.1")).to be < v("1.0.0")
  end

  it "compares prerelease identifiers" do
    expect(v("1.0.0-alpha.1")).to be < v("1.0.0-alpha.beta")
    expect(v("1.0.0-beta")).to be > v("1.0.0-alpha.1")
    expect(v("1.0.0-alpha")).to be < v("1.0.0-alpha.1")
  end

  it "treats equal versions as equal" do
    expect(v("1.2.3-x")).to eq(v("1.2.3-x"))
    expect(v("1.2.3") <=> "1.2.3").to be_nil
  end

  describe "#bump" do
    it "resets lower parts" do
      expect(v("1.2.3").bump(:major).to_s).to eq("2.0.0")
      expect(v("1.2.3").bump(:minor).to_s).to eq("1.3.0")
      expect(v("1.2.3").bump(:patch).to_s).to eq("1.2.4")
    end

    it "releases a prerelease on patch bump" do
      expect(v("1.2.3-rc.1").bump(:patch).to_s).to eq("1.2.3")
    end
  end
end
