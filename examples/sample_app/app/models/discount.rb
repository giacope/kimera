# frozen_string_literal: true

# Plain-Ruby stand-in for an ActiveRecord model: rich in comparisons, boolean
# connectives and literals so the operator set has plenty to chew on, but with
# no database dependency so the fixture runs anywhere.
class Discount
  attr_reader :amount, :customer_tier, :coupon

  def initialize(amount:, customer_tier: :standard, coupon: nil)
    @amount = amount
    @customer_tier = customer_tier
    @coupon = coupon
  end

  # Eligible when the order is large enough, OR the customer is premium with a
  # coupon present.
  def eligible?(order_total)
    return false if order_total <= 0

    order_total >= 100 || (premium? && coupon_present?)
  end

  def premium?
    customer_tier == :premium
  end

  def coupon_present?
    !coupon.nil?
  end

  # Capped percentage applied to the order.
  def percentage
    if amount > 50
      50
    else
      amount
    end
  end

  def apply(order_total)
    return order_total unless eligible?(order_total)

    discounted = order_total - (order_total * percentage / 100.0)
    discounted < 0 ? 0 : discounted
  end
end
