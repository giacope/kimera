# frozen_string_literal: true

require "parser"
require_relative "unparse_precedence"

module Kimera
  class Unparse
    class Grouping
      NUMERALS = %i[int float rational complex].freeze
      CHAINS = %i[send csend index block numblock itblock].freeze
      SIGNS = %i[-@ +@].freeze
      PRECEDENCE = Precedence.new

      def initialize(node)
        @node = node
      end

      def call
        node = @node
        return node unless node.is_a?(Parser::AST::Node)
        children = node.children.map { |child| Grouping.new(child).call }
        PRECEDENCE.floors(node).each { |index, floor| children[index] = wrap(children[index], floor) }
        node.updated(nil, separate(node, children))
      end

      private

      def wrap(node, floor) = node && PRECEDENCE.tightness(node) < floor ? enclose(node) : node

      def enclose(node) = Parser::AST::Node.new(:begin, [node])

      def separate(node, children)
        receiver, *rest = children
        fused?(node, receiver) ? [enclose(receiver), *rest] : children
      end

      def fused?(node, receiver)
        selector = node.children[1] if node.type == :send
        (SIGNS.include?(selector) && rooted?(receiver)) || (selector == :** && negative?(receiver))
      end

      def rooted?(node) = CHAINS.include?(node&.type) && leading?(node.children.first)

      def leading?(node) = numeral?(node) || rooted?(node)

      def numeral?(node) = NUMERALS.include?(node&.type)

      def negative?(node)
        return false unless numeral?(node)
        value = node.children.first
        (value.is_a?(Complex) ? value.imaginary : value).to_s.start_with?("-")
      end
    end
  end
end
