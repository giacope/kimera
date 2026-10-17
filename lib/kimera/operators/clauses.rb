# frozen_string_literal: true

require_relative "vocabulary"

module Kimera
  module Operators
    module Clauses
      DEFINITION = /\Adef\b/

      module_function

      def begin(node)
        return unless node.is_a?(SyntaxTypes::BeginNode)
        node if node.begin_keyword_loc || node.location.slice.match?(DEFINITION)
      end

      def rescues(node)
        clause = self.begin(node)&.rescue_clause
        found = []
        while clause
          found << clause
          clause = following(clause)
        end
        found
      end

      def following(clause) = clause.respond_to?(:subsequent) ? clause.subsequent : clause.consequent
    end
  end
end
