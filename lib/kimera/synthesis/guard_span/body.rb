# frozen_string_literal: true

class Kimera::GuardSpan::Body
  def initialize(node)
    @node = node
  end

  def from = opening.location.start_offset

  def to = node.end_keyword_loc.start_offset

  def slice = node.slice.byteslice(from - node.location.start_offset, to - from)

  def text(written) = "begin; #{written}end"

  private

  def opening = [node.statements, node.rescue_clause, node.else_clause, node.ensure_clause].compact.first

  attr_reader :node
end
