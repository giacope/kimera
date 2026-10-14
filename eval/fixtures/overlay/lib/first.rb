limit = 10
FIRST_OVER = ->(value) { value > limit }

module First
  def self.over?(value) = FIRST_OVER.call(value)
end
