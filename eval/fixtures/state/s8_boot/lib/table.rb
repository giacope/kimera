require_relative "rate"

class Table
  RATES = (1..20).to_h { |x| [x, Rate.compute(x)] }.freeze

  def self.lookup(x) = RATES.fetch(x)
end
