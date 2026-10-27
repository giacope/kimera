# frozen_string_literal: true

module Kimera
  class Scribe
    class Texts
      SEALED = %i[def_node class_node module_node singleton_class_node].freeze

      def initialize(slices = {}.compare_by_identity)
        @slices = slices
        @calls = {}.compare_by_identity
      end

      def of(node, locals) = (@slices[node] unless locals.intersect?(calls(node)))

      private

      def calls(node) = @calls[node] ||= called(node).freeze

      def called(node)
        type = node.type
        own = type == :call_node && node.variable_call? ? Set[node.name] : Set.new
        inner = SEALED.include?(type) ? [] : node.compact_child_nodes
        inner.reduce(own) { |names, child| names | calls(child) }
      end
    end
  end
end
