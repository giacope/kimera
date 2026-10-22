# frozen_string_literal: true

require "parser"

module Kimera
  class Unparse
    class Precedence
      LOOSEST_FIRST = [
        %i[irange erange], %i[or], %i[and], %i[<=> == === != =~ !~], %i[> >= < <=], %i[| ^], %i[&], %i[<< >>],
        %i[+ -], %i[* / %], %i[-@], %i[**], %i[! ~ +@]
      ].freeze
      NONASSOCIATIVE = %i[<=> == === != =~ !~ irange erange].freeze
      RIGHT_ASSOCIATIVE = %i[**].freeze
      OPERATORS = LOOSEST_FIRST.flatten.freeze
      PREFIX = %i[! ~ +@ -@].freeze
      UNCLOSED = %i[
        lvasgn ivasgn gvasgn cvasgn casgn masgn op_asgn or_asgn and_asgn indexasgn rescue match_pattern match_pattern_p
      ].freeze
      CALLS = %i[send csend index indexasgn].freeze
      SPREAD = %i[splat kwargs block_pass].freeze

      def floors(node)
        level = operator(node)
        return receivers(node) unless level
        prefix?(node) ? operand(node, 0, level) : infix(node, level)
      end

      def tightness(node) = UNCLOSED.include?(node.type) || assignment?(node) ? -1 : operator(node) || Float::INFINITY

      private

      def receivers(node) = CALLS.include?(node.type) && node.children[0] ? [[0, Float::INFINITY]] : []

      def infix(node, level)
        selector = key(node)
        right = RIGHT_ASSOCIATIVE.include?(selector)
        left = right || NONASSOCIATIVE.include?(selector) ? 1 : 0
        [[0, level + left], *operand(node, node.type == :send ? 2 : 1, level + (right ? 0 : 1))]
      end

      def operand(node, index, floor) = prefix?(node.children[index]) ? [] : [[index, floor]]

      def operator(node)
        return if node.type == :send && !infix?(node) && !prefix?(node)
        LOOSEST_FIRST.index { |level| level.include?(key(node)) }
      end

      def key(node)
        type = node.type
        type == :send ? node.children[1] : type
      end

      def infix?(node)
        arguments = node.children.drop(2)
        arguments.one? && !SPREAD.include?(arguments[0].type)
      end

      def prefix?(node) = node.is_a?(Parser::AST::Node) && node.type == :send && PREFIX.include?(node.children[1])

      def assignment?(node)
        selector = node.children[1]
        node.type == :send && selector.end_with?("=") && !OPERATORS.include?(selector)
      end
    end
  end
end
