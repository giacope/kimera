# frozen_string_literal: true

require_relative "survey"

module Kimera
  module Operators
    class Enclosed < Survey
      def initialize(root, names, &pick)
        super(root)
        @names = names
        @pick = pick
      end

      private

      def nodes = visit(@root)

      def visit(node)
        return mark(node) if node.is_a?(SyntaxTypes::DefNode) && @names.include?(node.name)
        node.compact_child_nodes.flat_map { |child| visit(child) }
      end

      def mark(node)
        (@pick.call(node) ? [node] : []) + node.compact_child_nodes.flat_map { |child| mark(child) }
      end
    end
  end
end
