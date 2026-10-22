# frozen_string_literal: true

module Kimera
  class Scribe
    class Lines
      SPACED = %i[kwbegin def defs module class sclass].freeze

      def initialize(node, pen)
        @node = node
        @pen = pen
      end

      def text
        pens = Pens.new(@pen, statements).list
        statements.each_with_index.sum("") { |statement, index| line(statement, index, pens.fetch(index)) }
      end

      private

      def statements
        return [] unless @node
        @node.type == :begin && @node.children.size > 1 ? @node.children : [@node]
      end

      def line(statement, index, pen)
        written = pen.write(statement, Level::STATEMENT)
        gap = index.positive? && SPACED.include?(statement.type) ? "\n" : ""
        terminator = index < statements.size - 1 && written.end_with?("..") ? ";" : ""
        "#{gap}\n#{@pen.margin}#{written}#{terminator}"
      end
    end
  end
end
