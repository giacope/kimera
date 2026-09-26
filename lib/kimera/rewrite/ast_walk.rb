# frozen_string_literal: true

module Kimera
  module Rewrite
    module AstWalk
      module_function

      def rebuild(node, &)
        return node unless node.is_a?(Parser::AST::Node)
        yield(node.updated(nil, node.children.map { |child| rebuild(child, &) }), node)
      end

      def visit(node, &)
        return unless node.is_a?(Parser::AST::Node)
        yield(node)
        node.children.each { |child| visit(child, &) }
      end
    end
  end
end
