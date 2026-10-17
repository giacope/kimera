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

      def collect(table) = table.tap { visit(@root, table) }

      def visit(node, table)
        return mark(node, table) if node.is_a?(SyntaxTypes::DefNode) && @names.include?(node.name)
        node.compact_child_nodes.each { |child| visit(child, table) }
      end

      def mark(node, table)
        table << node if @pick.call(node)
        node.compact_child_nodes.each { |child| mark(child, table) }
      end
    end
  end
end
