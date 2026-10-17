# frozen_string_literal: true

module Kimera
end

class Kimera::Listing
  LIMIT = 10

  def initialize(items)
    @items = items
  end

  def lines(indent)
    more = @items.size - LIMIT
    shown = @items.first(LIMIT).map { |item| "\n#{indent}#{item}" }.join
    more.positive? ? "#{shown}\n#{indent}… and #{more} more" : shown
  end
end
