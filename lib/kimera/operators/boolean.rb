# frozen_string_literal: true

require_relative "node_swap"

module Kimera
  module Operators
    BOOLEAN_OPERATORS = {
      BooleanConnective: [
        "boolean_connective",
        {
          AndNode => { label: "&& => ||", to: "or" },
          OrNode => { label: "|| => &&", to: "and" }
        }
      ],
      BooleanLiteral: [
        "boolean_literal",
        {
          TrueNode => { label: "true => false", to: "false" },
          FalseNode => { label: "false => true", to: "true" }
        }
      ]
    }.freeze

    BOOLEAN_OPERATORS.each { |name, (key, swaps)| const_set(name, NodeSwap.define(key, swaps)) }
  end
end
