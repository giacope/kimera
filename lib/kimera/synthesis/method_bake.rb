# frozen_string_literal: true

require_relative "overlay_splice"

class Kimera::Overlay::MethodBake
  include Kimera::OverlaySplice

  def initialize(map, tree)
    @map = map
    @tree = tree
  end

  def source(location)
    definition = definitions(@map.ast).find { |node| location.inside?(*span(node)) }
    text = definition && written(counterpart(definition))
    text && graft(definition, text)
  end

  private

  def written(node)
    Kimera::Scribe.new(node).source
  rescue StandardError
    nil
  end

  def graft(definition, text)
    spliced = @map.splice([span(definition) + [text]] + reopenings)
    spliced if Kimera::Syntax.parse(spliced).success?
  end

  def counterpart(definition)
    span = span(definition)
    definitions(@tree).find { |node| span(node) == span }
  end
end
