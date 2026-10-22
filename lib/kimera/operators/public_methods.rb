# frozen_string_literal: true

require_relative "survey"

module Kimera
  module Operators
    class PublicMethods
      include Survey

      BODIES = [SyntaxTypes::ClassNode, SyntaxTypes::ModuleNode, SyntaxTypes::SingletonClassNode].freeze
      HIDING = %i[private protected module_function].freeze
      SHOWING = %i[public].freeze

      def initialize(root)
        @root = root
      end

      private

      def nodes = visit(@root)

      def visit(node)
        body = node.body if BODIES.any? { |kind| node.is_a?(kind) }
        (body.is_a?(SyntaxTypes::StatementsNode) ? read(body.body) : []) +
          node.compact_child_nodes.flat_map { |child| visit(child) }
      end

      def read(statements)
        public = true
        candidates =
          statements.select do |statement|
            call = visibility(statement)
            public = toggled(call, public) if call
            public && method?(statement)
          end
        hidden = hidden(statements)
        candidates.reject { |definition| hidden.include?(definition.name) }
      end

      def toggled(call, public) = call.arguments ? public : !HIDING.include?(call.name)

      def hidden(statements)
        calls = statements.filter_map { |statement| visibility(statement) }.select { HIDING.include?(it.name) }
        calls.flat_map { |call| Array(call.arguments&.arguments).map { |argument| named(argument) } }
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
