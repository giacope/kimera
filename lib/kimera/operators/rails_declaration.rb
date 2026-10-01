# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::RailsDeclaration < Kimera::Operators::Base
  def body? = true

  def statement? = true

  def variants(node, **)
    return unless call(node).bare?(self.class::NAMES)
    declaration(node)
  end
end
