require_relative "box"

module Catalog
  def self.standard
    @standard ||= Box.new(width: 2 * 3, height: 4, depth: 10 / 2)
  end
end
