module Rules
  def self.even_bonus
    ->(n) { n.even? ? n / 2 : 0 }
  end

  def self.big_penalty
    ->(n) { n > 100 ? -(n - 100) : 0 }
  end

  def self.all
    { even: even_bonus, big: big_penalty }
  end
end
