# frozen_string_literal: true

require_relative "../scribe/nodes"

module Kimera
  module Rewrite
    class PinnedPredicate
      include Kimera::Scribe::Nodes

      BINDINGS = %i[lvasgn match_with_lvasgn].freeze

      def initialize(predicate)
        @predicate = predicate
      end

      def to(literal) = binds?(@predicate) ? ast(:begin, @predicate, literal) : literal

      private

      def binds?(tree)
        return false unless tree.is_a?(Parser::AST::Node)
        BINDINGS.include?(tree.type) || tree.children.any? { |child| binds?(child) }
      end
    end
  end
end
