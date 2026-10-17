# frozen_string_literal: true

module Kimera
  module Rewrite
    class Invocation
      def initialize(node)
        @node = node
      end

      def select(to)
        receiver, _selector, *arguments = @node.children
        @node.updated(nil, [receiver, to, *arguments])
      end

      def block
        return yield(@node) unless %i[block numblock].include?(@node.type)
        call, *rest = @node.children
        @node.updated(nil, [yield(call), *rest])
      end

      def rewrite(key, &)
        receiver, selector, *arguments = @node.children
        position = index(arguments)
        return @node unless position
        @node.updated(nil, [receiver, selector, *apply(arguments, position, key, &)])
      end

      private

      def index(arguments)
        arguments.rindex { |a| a.is_a?(Parser::AST::Node) && %i[kwargs hash].include?(a.type) }
      end

      def apply(arguments, position, key)
        hash = arguments[position]
        pairs = hash.children.filter_map { |pair| matches?(pair, key) ? yield(pair) : pair }
        arguments[0...position] + (pairs.empty? ? [] : [hash.updated(nil, pairs)]) + arguments[(position + 1)..]
      end

      def matches?(pair, key)
        symbol = pair.children.first
        pair.type == :pair && symbol.type == :sym &&
          symbol.children.first.to_s == key
      end
    end
  end
end
