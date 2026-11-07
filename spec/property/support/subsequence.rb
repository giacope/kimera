# frozen_string_literal: true

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
