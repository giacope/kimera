# frozen_string_literal: true

require_relative "survey"

module Kimera
  module Operators
    class Reassignments < Survey
      SCOPES = [
        SyntaxTypes::DefNode, SyntaxTypes::BlockNode, SyntaxTypes::LambdaNode, SyntaxTypes::ClassNode,
        SyntaxTypes::ModuleNode, SyntaxTypes::SingletonClassNode, SyntaxTypes::ProgramNode
      ].freeze
      BINDERS = /(ParameterNode|BlockLocalVariableNode)\z/
      WRITES = /LocalVariable\w*(Write|Target)Node\z/

      private

      def collect(table) = table.tap { visit(@root, Set.new, table) }

      def visit(node, bound, table)
        bound = Set.new(parameters(node)) if SCOPES.any? { |kind| node.is_a?(kind) }
        bind(node, bound, table) if node.class.name.match?(WRITES)
        node.compact_child_nodes.each { |child| visit(child, bound, table) }
      end

      def bind(node, bound, table)
        name = node.name
        table << node if rebound?(node, bound) && node.is_a?(SyntaxTypes::LocalVariableWriteNode)
        bound << name
      end

      def rebound?(node, bound) = node.depth.positive? || bound.include?(node.name)

      def parameters(node, found = [])
        held = node.respond_to?(:parameters) ? node.parameters : nil
        names(held, found) if held
        found
      end

      def names(node, found)
        found << node.name if node.class.name.match?(BINDERS) && node.respond_to?(:name) && node.name
        node.compact_child_nodes.each { |child| names(child, found) }
      end
    end
  end
end
