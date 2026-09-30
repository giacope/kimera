# frozen_string_literal: true

module Kimera
end

module Kimera::Listing
  LIMIT = 10

  module_function

  def lines(items, indent)
    more = items.size - LIMIT
    shown = items.first(LIMIT).map { |item| "\n#{indent}#{item}" }.join
    more.positive? ? "#{shown}\n#{indent}… and #{more} more" : shown
  end
end
