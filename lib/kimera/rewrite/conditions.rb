# frozen_string_literal: true

module Kimera
  module Rewrite
    class Conditions
      TESTS = %i[if while until while_post until_post].freeze
      NEGATION = [:!].freeze
      PASSAGES = %i[and or].freeze
      ENCLOSURES = %i[begin kwbegin].freeze
      READ_AS_CONDITIONS = %i[irange erange regexp].freeze

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
        return [] unless node.is_a?(Parser::AST::Node)
        [[node, tested]] +
          node.children.each_with_index.flat_map { |child, index| marks(child, carried(node, index, tested)) }
      end

      def carried(node, index, tested) = (index.zero? && tests?(node)) || (tested && passes?(node))

      def tests?(node)
        type = node.type
        TESTS.include?(type) || (type == :send && node.children.drop(1) == NEGATION)
      end

      def passes?(node)
        type = node.type
        PASSAGES.include?(type) || (ENCLOSURES.include?(type) && node.children.one?)
      end
    end
  end
end
