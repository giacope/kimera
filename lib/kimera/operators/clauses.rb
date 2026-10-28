# frozen_string_literal: true

require_relative "vocabulary"

module Kimera
  module Operators
    class Clauses
      DEFINITION = /\Adef\b/

      def initialize(node)
        @node = node
      end

      def begun
        return [] unless @node.is_a?(SyntaxTypes::BeginNode)
        @node.begin_keyword_loc || @node.location.slice.match?(DEFINITION) ? [@node] : []
      end

      def rescues = begun.flat_map { |node| chained(node.rescue_clause) }

      private

      def chained(clause) = clause ? [clause, *chained(following(clause))] : []

      def following(clause) = clause.respond_to?(:subsequent) ? clause.subsequent : clause.consequent
    end
  end
end
