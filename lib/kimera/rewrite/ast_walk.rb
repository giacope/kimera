# frozen_string_literal: true

module Kimera
  module Rewrite
    class AstWalk
      def initialize(root)
        @root = root
      end

      def rebuild(&) = rebuilt(@root, &)

      def visit(&) = visited(@root, &)

      private

      def rebuilt(node, &)
        return node unless node.is_a?(Parser::AST::Node)
        yield(node.updated(nil, node.children.map { |child| rebuilt(child, &) }), node)
      end

      def visited(node, &)
        return unless node.is_a?(Parser::AST::Node)
        yield(node)
        node.children.each { |child| visited(child, &) }
      end
    end
  end
end
