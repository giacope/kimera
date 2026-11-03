# frozen_string_literal: true

module Kimera
  class Scribe
    class Pen
      def initialize(texts, margin)
        @texts = texts
        @margin = margin
      end

      def form(node, scope, mode)
        kind = FORMS.fetch(node.type) { raise(ArgumentError, "kimera cannot write a #{node.type}") }
        kind.new(node, self, scope, mode)
      end

      def slice(node, scope, &) = @texts.of(node, scope, &)

      def lines(node, scope) = Lines.new(node, deeper, scope, @margin.deeper).text

      def newline = @margin.newline

      private

      def deeper = Pen.new(@texts, @margin.deeper)
    end
  end
end
