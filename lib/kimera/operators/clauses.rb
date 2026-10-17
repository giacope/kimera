# frozen_string_literal: true

require_relative "vocabulary"

module Kimera
  module Operators
    class Clauses
      DEFINITION = /\Adef\b/

      def initialize(node)
        @node = node
      end

      def begin
        return unless @node.is_a?(SyntaxTypes::BeginNode)
        @node if @node.begin_keyword_loc || @node.location.slice.match?(DEFINITION)
      end

      def rescues
        clause = self.begin&.rescue_clause
        found = []
        while clause
          found << clause
          clause = following(clause)
        end
        found
      end

      private

      def following(clause) = clause.respond_to?(:subsequent) ? clause.subsequent : clause.consequent
    end
  end
end
