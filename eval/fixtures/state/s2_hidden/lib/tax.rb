module Tax
  def self.rate(region)
    region == :eu ? 20 : 5
  end

  def self.exempt?(region)
    region == :gb || region == :ch
  end
end
