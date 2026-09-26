# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::RailsDeclaration < Kimera::Operators::Base
  class << self
    def body? = true

    def statement? = true
  end

  def variants(node, **)
    return unless call(node).bare?(self.class::NAMES)
    declaration(node)
  end
end
