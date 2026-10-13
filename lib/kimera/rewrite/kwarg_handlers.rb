# frozen_string_literal: true

module Kimera
  module Rewrite
    module KwargHandlers
      module_function

      def select(call, to)
        receiver, _selector, *arguments = call.children
        call.updated(nil, [receiver, to, *arguments])
      end

      def block(node)
        return yield(node) unless %i[block numblock].include?(node.type)
        call, *rest = node.children
        node.updated(nil, [yield(call), *rest])
      end

      def rewrite(call, key, &)
        receiver, selector, *arguments = call.children
        position = index(arguments)
        return call unless position
        apply(arguments, position, key, &)
        call.updated(nil, [receiver, selector, *arguments])
      end

      def index(arguments)
        arguments.rindex { |a| a.is_a?(Parser::AST::Node) && %i[kwargs hash].include?(a.type) }
      end

      def apply(arguments, position, key)
        hash = arguments[position]
        pairs = hash.children.filter_map { |pair| matches?(pair, key) ? yield(pair) : pair }
        pairs.empty? ? arguments.delete_at(position) : arguments[position] = hash.updated(nil, pairs)
      end

      def matches?(pair, key)
        symbol = pair.children.first
        pair.type == :pair && symbol.type == :sym &&
          symbol.children.first.to_s == key
      end
    end
  end
end
