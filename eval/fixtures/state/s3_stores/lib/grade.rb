module Grade
  def self.letter(score)
    return "A" if score >= 90
    return "B" if score >= 80
    "C"
  end

  def self.passing?(score)
    score >= 60 && score <= 100
  end

  def self.label(score)
    !passing?(score) ? "fail" : "pass"
  end
end
