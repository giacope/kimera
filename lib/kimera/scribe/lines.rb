# frozen_string_literal: true

module Kimera
  class Scribe
    class Lines
      SPACED = %i[def_node class_node module_node singleton_class_node].freeze

      def initialize(node, pen, joint = nil)
        @node = node
        @pen = pen
        @joint = joint
      end

      def text
        pens = Pens.new(@pen, statements).list
        statements.each_with_index.sum("") { |statement, index| line(statement, index, pens.fetch(index)) }
      end

      private

      def statements = @_statements ||= flat(@node)

      def flat(node)
        return [] unless node
        node.type == :statements_node ? node.body.flat_map { |statement| flat(statement) } : [node]
      end

      def line(statement, index, pen)
        written = pen.write(statement, Level::STATEMENT)
        terminator = index < statements.size - 1 && written.end_with?("..") ? ";" : ""
        return "#{@joint if index.positive?}#{written}#{terminator}" if @joint
        "#{@pen.gap if index.positive? && spaced?(statement)}#{@pen.newline}#{written}#{terminator}"
      end

      def spaced?(statement)
        SPACED.include?(statement.type) || (statement.type == :begin_node && statement.begin_keyword_loc)
      end
    end
  end
end
