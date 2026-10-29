# frozen_string_literal: true

require_relative "line_pad"
require_relative "readback"
require_relative "overlay_splice"
require_relative "splice_reopening"

class Kimera::Overlay::MethodBake
  include Kimera::OverlaySplice

  def initialize(map, tree)
    @map = map
    @tree = tree
  end

  def source(location)
    definitions(@map.ast).lazy.select { |node| location.inside?(*span(node)) }.first(1).flat_map do |definition|
      counterparts(definition).flat_map { |node| written(definition, node) { [] } }.flat_map { graft(definition, it) }
    end
  end

  private

  def written(definition, node)
    Kimera::LinePad.new(definition.slice).fits(Kimera::Scribe.new(node), Kimera::Readback.new(node))
  rescue StandardError
    yield
  end

  def graft(definition, text)
    spliced = @map.splice([span(definition) + [text]] + Kimera::SpliceReopening.new(@map).edits)
    Kimera::Syntax.parse(spliced).success? ? [spliced] : []
  end

  def counterparts(definition)
    span = span(definition)
    definitions(@tree).lazy.select { |node| span(node) == span }.first(1)
  end
end
