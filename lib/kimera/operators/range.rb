# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::Range < Kimera::Operators::Base
  def key = "range"

  def variants(node, **)
    return unless node.is_a?(RangeNode)
    return solo("... => ..", "range_flip", to: "irange") if node.exclude_end?
    solo(".. => ...", "range_flip", to: "erange")
  end
end
