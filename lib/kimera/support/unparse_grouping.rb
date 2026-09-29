# frozen_string_literal: true

require "parser"

module Kimera
  module Unparse
    module Grouping
      module_function

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

      def call(node)
        return node unless node.is_a?(Parser::AST::Node)
        children = node.children.map { |child| call(child) }
        floors(node).each { |index, floor| children[index] = wrap(children[index], floor) }
        node.updated(nil, children)
      end

      def wrap(node, floor) = node && tightness(node) < floor ? Parser::AST::Node.new(:begin, [node]) : node

      def floors(node)
        level = operator(node)
        return receivers(node) unless level
        return operand(node, 0, level) if prefix?(node)
        selector = key(node)
        [[0, level + left(selector)], *operand(node, node.type == :send ? 2 : 1, level + right(selector))]
      end

      def operand(node, index, floor) = prefix?(node.children[index]) ? [] : [[index, floor]]

      def left(selector) = NONASSOCIATIVE.include?(selector) || RIGHT_ASSOCIATIVE.include?(selector) ? 1 : 0

      def right(selector) = RIGHT_ASSOCIATIVE.include?(selector) ? 0 : 1

      def receivers(node) = CALLS.include?(node.type) && node.children[0] ? [[0, Float::INFINITY]] : []

      def tightness(node) = UNCLOSED.include?(node.type) || assignment?(node) ? -1 : operator(node) || Float::INFINITY

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
