# frozen_string_literal: true

module Kimera
  class Scribe
    class Clauses
      def initialize(node, pen, scope, mode)
        @node = node
        @pen = pen
        @scope = scope
        @mode = mode
      end

      def text = structured? ? structure : @pen.lines(@node, @scope)

      def structured? = @node&.type == :begin_node && !@node.begin_keyword_loc

      def structure
        handlers = Kimera::Rescues.new(@node.rescue_clause).to_a
        body = @pen.lines(@node.statements, @scope)
        "#{body}#{handling(handlers)}#{fallback(handlers)}#{cleanup(handlers)}"
      end

      private

      def handling(handlers)
        scopes = Scopes.new(@scope.with([@node.statements]), handlers).list
        handlers.zip(scopes).sum("") { |handler, scope| Rescue.new(handler, @pen, scope, @mode).text }
      end

      def fallback(handlers)
        otherwise = @node.else_clause
        otherwise ? "#{keyword("else")}#{@pen.lines(otherwise.statements, after(handlers))}" : ""
      end

      def cleanup(handlers)
        ensure_clause = @node.ensure_clause
        return "" unless ensure_clause
        "#{keyword("ensure")}#{@pen.lines(ensure_clause.statements, after([*handlers, @node.else_clause]))}"
      end

      def after(nodes) = @scope.with([@node.statements, *nodes.compact])

      def keyword(word) = "#{@pen.newline}#{word}"
    end
  end
end
