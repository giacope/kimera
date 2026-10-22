# frozen_string_literal: true

module Kimera
  class Scribe
    class Clauses
      def initialize(node, pen)
        @node = node
        @pen = pen
      end

      def text
        case @node&.type
        when :ensure then guarded
        when :rescue then rescued(@node)
        else Lines.new(@node, @pen.deeper).text
        end
      end

      private

      def guarded
        body, cleanup = @node.children
        "#{Clauses.new(body, @pen).text}#{keyword("ensure")}#{Lines.new(cleanup, @pen.with([body]).deeper).text}"
      end

      def rescued(node)
        body, *handlers, fallback = node.children
        text = Lines.new(body, @pen.deeper).text + handling(body, handlers)
        fallback ? "#{text}#{keyword("else")}#{Lines.new(fallback, @pen.with([body, *handlers]).deeper).text}" : text
      end

      def handling(body, handlers)
        pens = Pens.new(@pen, [body, *handlers]).list
        handlers.zip(pens.drop(1)).sum("") { |handler, pen| handled(handler, pen) }
      end

      def handled(handler, pen)
        classes, target, body = handler.children
        head = "rescue"
        head += " #{Exceptions.new(classes, pen).text}" if classes
        head += " => #{Target.new(target, pen).text}" if target
        "#{keyword(head)}#{Lines.new(body, pen.with([classes, target]).deeper).text}"
      end

      def keyword(word) = "\n#{@pen.margin}#{word}"
    end
  end
end
