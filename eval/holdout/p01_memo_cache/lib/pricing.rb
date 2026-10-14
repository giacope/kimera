require_relative "memo"

class Pricing
  TIERS = { gold: 15, silver: 10, bronze: 5 }.freeze

  def self.price(amount, tier)
    Memo.fetch([:price, amount, tier]) do
      pct = TIERS.fetch(tier, 0)
      discounted = amount - (amount * pct / 100)
      discounted < 10 ? 10 : discounted
    end
  end

  def self.bulk?(qty)
    qty >= 20 && qty <= 500
  end
end
