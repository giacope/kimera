# frozen_string_literal: true

module Kimera
  class Scribe
    class Lines
      SPACED = %i[def_node class_node module_node singleton_class_node].freeze

      def initialize(node, pen, scope, margin)
        @node = node
        @pen = pen
        @scope = scope
        @margin = margin
      end

      def text
        scopes = Scopes.new(@scope, statements).list
        statements.each_with_index.sum("") { |statement, index| line(statement, index, scopes.fetch(index)) }
      end

      private

      def statements = @_statements ||= flat(@node)

      def flat(node)
        return [] unless node
        node.type == :statements_node ? node.body.flat_map { |statement| flat(statement) } : [node]
      end

      def line(statement, index, scope)
        written = @pen.form(statement, scope, OPEN).written(STATEMENT)
        terminator = index < statements.size - 1 && written.end_with?("..") ? ";" : ""
        "#{@margin.gap if index.positive? && spaced?(statement)}#{@margin.newline}#{written}#{terminator}"
      end

      def spaced?(statement)
        SPACED.include?(statement.type) || (statement.type == :begin_node && statement.begin_keyword_loc)
      end
    end
  end
end
