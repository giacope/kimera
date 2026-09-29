# frozen_string_literal: true

# Whether `kept` appears in `whole` in order, not necessarily contiguously.
# Greedy matching is exact for this: taking the earliest match for each
# element never rules out a later one.
module Subsequence
  module_function

  def of?(kept, whole)
    cursor = 0
    kept.all? do |item|
      found = (cursor...whole.size).find { |index| whole[index] == item }
      cursor = found + 1 if found
      found
    end
  end
end
