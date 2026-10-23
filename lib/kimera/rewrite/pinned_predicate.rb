# frozen_string_literal: true

require_relative "../scribe/nodes"

module Kimera
  module Rewrite
    class PinnedPredicate
      include Kimera::Scribe::Nodes

      BINDINGS = /\A(?:local_variable_(?:operator_|or_|and_)?write|local_variable_target|match_write)_node\z/

      def initialize(predicate)
        @predicate = predicate
      end

      def to(literal) = binds?(@predicate) ? grouped([@predicate, literal]) : literal

      private

      def binds?(tree) = tree.type.match?(BINDINGS) || tree.compact_child_nodes.any? { |child| binds?(child) }
    end
  end
end
