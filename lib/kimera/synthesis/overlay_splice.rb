# frozen_string_literal: true

module Kimera
  module OverlaySplice
    private

    def definitions(root)
      nodes = []
      Kimera::Rewrite::AstWalk.new(root).visit { |node| nodes << node if node.type == :def_node }
      nodes
    end

    def span(node) = [node.location.start_offset, node.location.end_offset]
  end
end
