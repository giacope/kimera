# frozen_string_literal: true

require_relative "walking"

class Kimera::RegistryScan::Skipped
  include Kimera::RegistryWalking

  def initialize(nodes)
    @nodes = nodes
  end

  def lines = @nodes.flat_map { |node| own(node) }.sort

  private

  def own(node)
    location = node.location
    blanked(node, location).lines.each_with_index.filter_map do |line, index|
      location.start_line + index unless line.strip.empty?
    end
  end

  def blanked(node, location)
    from = location.start_offset
    nested(node).each_with_object(location.slice.b) do |inner, text|
      start = inner.start_offset - from
      text[start, inner.length] = text.byteslice(start, inner.length).tr("^\n", " ")
    end
  end

  def nested(node)
    body = deferred(node)
    node.compact_child_nodes.flat_map do |child|
      reexecuted?(child) || child.equal?(body) ? [child.location] : nested(child)
    end
  end
end
