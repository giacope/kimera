module Tally
  def self.evens(limit)
    count = 0
    index = 0
    while index < limit
      count += 1 if index.even? && index >= 0
      index += 1
    end
    count
  end
end
