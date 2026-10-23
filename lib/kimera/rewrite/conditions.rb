# frozen_string_literal: true

module Kimera
  module Rewrite
    class Conditions
      TESTS = %i[if_node unless_node while_node until_node].freeze
      PASSAGES = %i[and_node or_node parentheses_node program_node].freeze
      READ_AS_CONDITIONS = %i[range_node regular_expression_node interpolated_regular_expression_node].freeze

      def initialize(root, tested: false)
        @root = root
        @tested = tested
      end

      def places
        marks(@root, @tested).each_with_object({}.compare_by_identity) { |(node, test), found| found[node] = test }
      end

      def misread? = places.any? { |node, test| test && literal?(node) }

      private

      def literal?(node) = READ_AS_CONDITIONS.include?(node.type)

      def marks(node, tested)
        [[node, tested]] + node.compact_child_nodes.flat_map { |child| marks(child, carried(node, child, tested)) }
      end

      def carried(node, child, tested) = tests?(node, child) || (tested && passes?(node, child))

      def tests?(node, child)
        type = node.type
        return node.predicate.equal?(child) if TESTS.include?(type)
        type == :call_node && node.name == :! && !node.arguments && node.receiver.equal?(child)
      end

      def passes?(node, child)
        case node.type
        when *PASSAGES then true
        when :statements_node then node.body.one?
        when :begin_node then child.equal?(node.statements)
        else false
        end
      end
    end
  end
end
