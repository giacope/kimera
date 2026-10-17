# frozen_string_literal: true

require_relative "base"
require_relative "clauses"

class Kimera::Operators::RescueClause < Kimera::Operators::Base
  def key = "rescue_clause"

  def variants(node, **)
    return solo("drop `rescue` modifier", "drop_rescue", index: 0) if node.is_a?(RescueModifierNode)
    Kimera::Operators::Clauses.new(node).rescues.each_with_index.map do |clause, index|
      Kimera::Operators::Variant.new(
        label: "drop `#{first(clause)}`",
        directive: directive("drop_rescue", index: index)
      )
    end
  end
end
