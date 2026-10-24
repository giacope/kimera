# frozen_string_literal: true

require_relative "base"

# Drops one `when` of a `case` that has another, so a branch no test takes
# shows up (`when 3000..Float::INFINITY then "critical"`); the value it would
# have chosen falls through to the next `when` or the `else`.
class Kimera::Operators::WhenClause < Kimera::Operators::Base
  def key = "when_clause"

  def variants(node, **)
    return unless node.type == :case_node && node.conditions.size > 1
    node.conditions.each_with_index.map do |clause, index|
      mutation("drop `#{first(clause)}`", "drop_when", index: index)
    end
  end
end
