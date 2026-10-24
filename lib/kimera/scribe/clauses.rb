# frozen_string_literal: true

module Kimera
  class Scribe
    class Clauses
      def initialize(node, pen)
        @node = node
        @pen = pen
      end

      def text = structured? ? structure : Lines.new(@node, @pen.deeper).text

      def structured? = @node&.type == :begin_node && !@node.begin_keyword_loc

      def structure
        handlers = Kimera::Syntax::RESCUES.call(@node.rescue_clause)
        body = Lines.new(@node.statements, @pen.deeper).text
        "#{body}#{handling(handlers)}#{fallback(handlers)}#{cleanup(handlers)}"
      end

      private

      def handling(handlers)
        pens = Pens.new(@pen.with([@node.statements]), handlers).list
        handlers.zip(pens).sum("") { |handler, pen| Rescue.new(handler, pen).text }
      end

      def fallback(handlers)
        otherwise = @node.else_clause
        otherwise ? "#{keyword("else")}#{Lines.new(otherwise.statements, after(handlers).deeper).text}" : ""
      end

      def cleanup(handlers)
        ensure_clause = @node.ensure_clause
        return "" unless ensure_clause
        "#{keyword("ensure")}#{Lines.new(ensure_clause.statements, after([*handlers, @node.else_clause]).deeper).text}"
      end

      def after(nodes) = @pen.with([@node.statements, *nodes.compact])

      def keyword(word) = "#{@pen.newline}#{word}"
    end
  end
end
