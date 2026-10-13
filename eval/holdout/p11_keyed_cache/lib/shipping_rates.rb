module ShippingRates
  def self.compute(weight, zone)
    base = zone == :intl ? 1500 : 500
    extra = weight > 2 ? (weight - 2) * 200 : 0
    total = base + extra
    weight >= 20 ? total * 9 / 10 : total
  end
end
