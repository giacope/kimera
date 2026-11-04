# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::ElementDrop < Kimera::Operators::Base
  SPLATS = { ArrayNode => SplatNode, HashNode => AssocSplatNode }.freeze

  def key = "element_drop"

  def variants(node, **)
    syntax(node).collections(SPLATS).flat_map { |elements, splat| drop(elements, splat) }
  end

  private

  def drop(elements, splat)
    return [] unless droppable?(elements, splat)
    drops(elements, "drop_element", label: "drop")
  end

  def droppable?(elements, splat)
    elements.length > 1 && elements.none?(splat)
  end
end
