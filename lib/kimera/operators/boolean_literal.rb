# frozen_string_literal: true

require_relative "node_swap"

class Kimera::Operators::BooleanLiteral < Kimera::Operators::NodeSwap
  def key = "boolean_literal"
end
