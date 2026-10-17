# frozen_string_literal: true

require_relative "base"
require_relative "clauses"

class Kimera::Operators::EnsureClause < Kimera::Operators::Base
  def key = "ensure_clause"

  def variants(node, **)
    solo("drop `ensure`", "drop_ensure") if Kimera::Operators::Clauses.begin(node)&.ensure_clause
  end
end
