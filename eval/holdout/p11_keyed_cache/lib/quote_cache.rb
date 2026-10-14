require_relative "shipping_rates"

module QuoteCache
  QUOTES = Hash.new { |h, key| h[key] = ShippingRates.compute(*key) }

  def self.quote(weight, zone)
    QUOTES[[weight, zone]]
  end
end
