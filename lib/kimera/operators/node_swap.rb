# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::NodeSwap < Kimera::Operators::Base
  SWAPS = {
    "boolean_connective" => {
      AndNode => { label: "&& => ||", to: "or" },
      OrNode => { label: "|| => &&", to: "and" }
    },
    "boolean_literal" => {
      TrueNode => { label: "true => false", to: "false" },
      FalseNode => { label: "false => true", to: "true" }
    }
  }.freeze

  def variants(node, **)
    swap = SWAPS.fetch(key)[node.class]
    return unless swap
    solo(swap[:label], key, to: swap[:to])
  end
end
