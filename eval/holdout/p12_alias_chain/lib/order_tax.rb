require_relative "order"

class Order
  alias_method :total_before_tax, :total

  def total
    t = total_before_tax
    t + t / 10
  end
end
