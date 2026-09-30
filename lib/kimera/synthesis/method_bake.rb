# frozen_string_literal: true

require_relative "overlay_splice"

class Kimera::Overlay::MethodBake
  include Kimera::OverlaySplice

  def initialize(map, tree)
    @map = map
    @tree = tree
  end

  def source(location)
    definition = definitions(@map.ast).find { |node| location.within?(*@map.span(node.location.expression)) }
    text = definition && written(counterpart(definition))
    text && graft(definition, text)
  end

  private

  def written(node)
    Kimera::Unparse.unparse(node)
  rescue StandardError
    nil
  end

  def graft(definition, text)
    spliced = apply([span(definition) + [text]] + reopenings)
    spliced if Kimera::Syntax.parse(spliced).success?
  end

  def counterpart(definition)
    expression = definition.location.expression
    definitions(@tree).find { |node| node.location.expression == expression }
  end
end
