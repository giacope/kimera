# frozen_string_literal: true

RSpec.describe Fx do
  describe ".rate" do
    it "is 1.0 for the same currency" do
      expect(described_class.rate("GBP", "GBP")).to eq(1.0)
    end

    it "derives cross rates through USD" do
      expect(described_class.rate("USD", "EUR")).to eq(0.92)
      expect(described_class.rate("EUR", "GBP")).to eq(0.858696)
      expect(described_class.rate("GBP", "JPY")).to eq(189.240506)
    end

    it "raises for an unknown currency on either side" do
      expect { described_class.rate("XXX", "USD") }.to raise_error(Fx::UnknownCurrency, /XXX/)
      expect { described_class.rate("USD", "YYY") }.to raise_error(Fx::UnknownCurrency, /YYY/)
    end

    it "serves a rate seeded straight into the cache" do
      # Leaves USD/ZZZ in this thread's cache for the rest of the run.
      described_class.cache["USD/ZZZ"] = 3.5
      expect(described_class.rate("USD", "ZZZ")).to eq(3.5)
    end
  end

  describe ".convert" do
    it "rounds to cents" do
      expect(described_class.convert(100, "EUR", "USD")).to eq(108.7)
      expect(described_class.convert(10, "CHF", "GBP")).to eq(8.98)
    end

    it "rounds zero-decimal currencies to whole units" do
      expect(described_class.convert(12.34, "USD", "JPY")).to eq(1845)
    end

    it "converts zero" do
      expect(described_class.convert(0, "USD", "EUR")).to eq(0)
    end

    it "rejects negative amounts" do
      expect { described_class.convert(-1, "USD", "EUR") }.to raise_error(ArgumentError)
    end
  end

  describe ".quote" do
    it "spreads around the mid rate" do
      expect(described_class.quote("USD", "CHF")).to eq(bid: 0.8789, ask: 0.8811)
    end

    it "takes a custom spread" do
      expect(described_class.quote("USD", "GBP", spread_bps: 100)).to eq(bid: 0.78605, ask: 0.79395)
    end
  end

  describe ".with_rates" do
    it "uses the override table and a private cache inside the block" do
      described_class.rate("USD", "EUR")
      inside = described_class.with_rates("EUR" => 0.5) { described_class.convert(10, "USD", "EUR") }
      expect(inside).to eq(5.0)
      expect(described_class.convert(10, "USD", "EUR")).to eq(9.2)
    end

    it "restores the outer state after an exception" do
      expect do
        described_class.with_rates("EUR" => 0.5) { raise "boom" }
      end.to raise_error("boom")
      expect(described_class.rates).to equal(Fx::RATES)
    end
  end
end
