require_relative "rate"

class Cache
  def self.get(x)
    (@store ||= {})[x] ||= Rate.compute(x)
  end
end
