# frozen_string_literal: true

require_relative "node_swap"

class Kimera::Operators::BooleanConnective < Kimera::Operators::NodeSwap
  def key = "boolean_connective"
end
