class Band
  def self.of(age)
    return :child if age < 13
    return :teen if age < 20
    :adult
  end
end
