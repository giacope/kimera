module Price
  TABLE = { 1 => 10, 2 => 20, 3 => 27, 4 => 36 }.freeze

  def self.of(quantity)
    return TABLE.fetch(quantity) if ENV["PRICE_TABLE"] == "1"
    bulk = quantity > 2
    bulk ? quantity * 9 : quantity * 10
  end
end
