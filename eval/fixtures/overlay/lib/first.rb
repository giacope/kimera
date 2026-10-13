limit = 10

module First
  OVER = ->(value) { value > limit }

  def self.over?(value) = OVER.call(value)
end
