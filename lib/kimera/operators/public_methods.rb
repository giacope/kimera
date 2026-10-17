# frozen_string_literal: true

require_relative "survey"

module Kimera
  module Operators
    class PublicMethods < Survey
      BODIES = [SyntaxTypes::ClassNode, SyntaxTypes::ModuleNode, SyntaxTypes::SingletonClassNode].freeze
      HIDING = %i[private protected module_function].freeze
      SHOWING = %i[public].freeze

      private

      def collect(table) = table.tap { visit(@root, table) }

      def visit(node, table)
        body = node.body if BODIES.any? { |kind| node.is_a?(kind) }
        read(body.body, table) if body.is_a?(SyntaxTypes::StatementsNode)
        node.compact_child_nodes.each { |child| visit(child, table) }
      end

      def read(statements, table)
        hidden = Set.new
        public = true
        candidates = []
        statements.each do |statement|
          call = visibility(statement)
          next public = toggled(call, public, hidden) if call
          candidates << statement if public && method?(statement)
        end
        candidates.each { |definition| table << definition unless hidden.include?(definition.name) }
      end

      def toggled(call, public, hidden)
        named = call.arguments&.arguments
        return !HIDING.include?(call.name) unless named
        named.each { |argument| hidden << named(argument) } if HIDING.include?(call.name)
        public
      end

      def visibility(statement)
        return unless statement.is_a?(SyntaxTypes::CallNode) && !statement.receiver
        statement if HIDING.include?(statement.name) || SHOWING.include?(statement.name)
      end

      def named(argument)
        case argument
        when SyntaxTypes::SymbolNode, SyntaxTypes::StringNode then argument.unescaped.to_sym
        when SyntaxTypes::DefNode then argument.name
        end
      end

      def method?(statement) = statement.is_a?(SyntaxTypes::DefNode) && !statement.receiver && statement.body
    end
  end
end
