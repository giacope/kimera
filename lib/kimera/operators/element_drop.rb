# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::ElementDrop < Kimera::Operators::Base
  SPLATS = { ArrayNode => SplatNode, HashNode => AssocSplatNode }.freeze

  class << self
    def key = "element_drop"
  end

  def variants(node, **)
    parts = collection(node)
    drop(*parts) if parts
  end

  private

  def collection(node)
    syntax(node).collection(SPLATS)
  end

  def drop(elements, splat)
    return unless droppable?(elements, splat)
    drops(elements, "drop_element", label: "drop")
  end

  def droppable?(elements, splat)
    elements.length > 1 && elements.none?(splat)
  end
end
