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

      class Scope
        def initialize(names)
          @names = Set.new(names)
        end

        def bound?(name) = @names.include?(name)

        def bind(name) = @names.add(name)
      end

      private

      def nodes = visit(@root, nil)

      def visit(node, scope)
        scope = Scope.new(parameters(node)) if SCOPES.any? { |kind| node.is_a?(kind) }
        (node.class.name.match?(WRITES) ? bind(node, scope) : []) +
          node.compact_child_nodes.flat_map { |child| visit(child, scope) }
      end

      def bind(node, scope)
        rebound = rebound?(node, scope) && node.is_a?(SyntaxTypes::LocalVariableWriteNode)
        scope.bind(node.name)
        rebound ? [node] : []
      end

      def rebound?(node, scope) = node.depth.positive? || scope.bound?(node.name)

      def parameters(node)
        held = node.respond_to?(:parameters) ? node.parameters : nil
        held ? names(held) : []
      end

      def names(node)
        (node.class.name.match?(BINDERS) && node.respond_to?(:name) && node.name ? [node.name] : []) +
          node.compact_child_nodes.flat_map { |child| names(child) }
      end
    end
  end
end
