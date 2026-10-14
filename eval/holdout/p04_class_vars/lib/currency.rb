require_relative "rate_table"

class Currency
  def self.rates
    @@rates ||= RateTable.build
  end

  def self.convert(cents, from, to)
    return cents if from == to

    (cents * rates.fetch(from) + rates.fetch(to) / 2) / rates.fetch(to)
  end
end

class Crypto < Currency
  def self.convert(cents, from, to)
    super(cents, from, to) * 2
  end
end
