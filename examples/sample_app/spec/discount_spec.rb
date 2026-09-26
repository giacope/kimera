# frozen_string_literal: true

require_relative "../app/models/discount"

RSpec.describe Discount do
  describe "#eligible?" do
    it "is false for non-positive totals" do
      expect(described_class.new(amount: 10).eligible?(0)).to be(false)
      expect(described_class.new(amount: 10).eligible?(-5)).to be(false)
    end

    it "is eligible for large orders" do
      expect(described_class.new(amount: 10).eligible?(100)).to be(true)
      expect(described_class.new(amount: 10).eligible?(250)).to be(true)
    end

    it "is eligible for premium customers with a coupon" do
      discount = described_class.new(amount: 10, customer_tier: :premium, coupon: "X")
      expect(discount.eligible?(20)).to be(true)
    end

    it "is not eligible for premium customers without a coupon" do
      discount = described_class.new(amount: 10, customer_tier: :premium)
      expect(discount.eligible?(20)).to be(false)
    end

    it "is not eligible for standard customers below threshold" do
      discount = described_class.new(amount: 10, coupon: "X")
      expect(discount.eligible?(20)).to be(false)
    end
  end

  describe "#percentage" do
    it "caps at 50" do
      expect(described_class.new(amount: 80).percentage).to eq(50)
    end

    it "passes through small amounts" do
      expect(described_class.new(amount: 30).percentage).to eq(30)
    end

    it "treats exactly 50 as uncapped" do
      expect(described_class.new(amount: 50).percentage).to eq(50)
    end
  end

  describe "#apply" do
    it "returns the original total when not eligible" do
      expect(described_class.new(amount: 10).apply(20)).to eq(20)
    end

    it "applies the percentage when eligible" do
      discount = described_class.new(amount: 10)
      expect(discount.apply(200)).to eq(180.0)
    end
  end
end
