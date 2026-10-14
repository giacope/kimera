module Money
  OPTIONS = { currency: "USD" }

  def self.format(cents)
    amount = cents / 100.0
    return "$#{"%.2f" % amount}" if OPTIONS[:currency] == "USD"
    "#{"%.2f" % amount} #{OPTIONS[:currency]}"
  end

  def self.round?(cents)
    cents % 100 == 0 && cents > 0
  end
end
