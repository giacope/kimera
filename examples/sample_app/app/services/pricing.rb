# frozen_string_literal: true

require_relative "../models/discount"

# A small service object combining several mutation-rich operators.
class Pricing
  def initialize(logger: nil)
    @logger = logger
  end

  def quote(order_total:, discount:)
    log("quoting #{order_total}")
    total = discount.apply(order_total)
    total = round(total)
    total
  end

  def free_shipping?(order_total, weight)
    order_total > 75 && weight < 20
  end

  private

  def round(value)
    (value * 100).round / 100.0
  end

  def log(message)
    @logger&.info(message)
  end
end
