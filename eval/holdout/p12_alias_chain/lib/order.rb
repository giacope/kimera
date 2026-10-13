class Order
  def initialize(items)
    @items = items
  end

  def subtotal
    @items.sum { |price, qty| price * qty }
  end

  def total
    s = subtotal
    s >= 1000 ? s - 100 : s
  end
end
