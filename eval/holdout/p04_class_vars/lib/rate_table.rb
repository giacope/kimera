module RateTable
  def self.build
    base = 100
    { "USD" => base, "EUR" => base + 10, "GBP" => base * 5 / 4 }
  end
end
