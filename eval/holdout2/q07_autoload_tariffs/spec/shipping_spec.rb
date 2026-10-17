# frozen_string_literal: true

RSpec.describe Shipping do
  describe ".quote" do
    it "prices the domestic first band" do
      expect(described_class.quote(500, "de")).to eq(570)
    end

    it "moves to the next band just above a limit" do
      expect(described_class.quote(501, "DE")).to eq(780)
      expect(described_class.quote(2_000, "DE")).to eq(990)
      expect(described_class.quote(5_000, "DE")).to eq(1_200)
      expect(described_class.quote(5_001, "DE")).to eq(1_410)
    end

    it "adds the zone surcharge" do
      expect(described_class.quote(1_000, "FR")).to eq(940)
      expect(described_class.quote(1_000, "US")).to eq(1_560)
    end

    it "charges rest of world above every listed zone" do
      expect(described_class.quote(1_000, "JP")).to eq(2_060)
    end

    it "charges per started kilo above ten kilos" do
      expect(described_class.quote(10_000, "DE")).to eq(1_410)
      expect(described_class.quote(10_001, "DE")).to eq(1_655)
      expect(described_class.quote(12_500, "DE")).to eq(1_725)
    end

    it "rounds express prices up" do
      expect(described_class.quote(500, "AT", express: true)).to eq(1_168)
      expect(described_class.quote(501, "DE", express: true)).to eq(1_248)
    end

    it "validates weight" do
      expect { described_class.quote(0, "DE") }.to raise_error(ArgumentError, /positive/)
      expect { described_class.quote(30_001, "DE") }.to raise_error(ArgumentError, /too heavy/)
      expect(described_class.quote(30_000, "DE")).to eq(2_320)
    end
  end

  it "picks the cheapest destination, alphabetically on ties" do
    expect(described_class.cheapest(800, %w[US NL BE GB])).to eq("BE")
  end
end
