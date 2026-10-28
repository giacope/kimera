# frozen_string_literal: true

Kimera::GuardSpan =
  Data.define(:node) do
    def self.of(node)
      bare = node.type == :begin_node && !node.begin_keyword_loc
      bare ? Kimera::GuardSpan::Body.new(node) : new(node)
    end

    def from = node.location.start_offset

    def to = node.location.end_offset

    def slice = node.slice

    def text(written) = written
  end

Kimera::GuardSpan::Body =
  Data.define(:node) do
    def from = opening.location.start_offset

    def opening = [node.statements, node.rescue_clause, node.else_clause, node.ensure_clause].compact.first

    def to = node.end_keyword_loc.start_offset

    def slice = node.slice.byteslice(from - node.location.start_offset, to - from)

    def text(written) = "begin; #{written}end"
  end
