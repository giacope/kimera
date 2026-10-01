# frozen_string_literal: true

module Kimera
  module Rewrite
    module KwargHandlers
      module_function

      def select(call, to)
        receiver, _selector, *args = call.children
        call.updated(nil, [receiver, to, *args])
      end

      def block(node)
        return yield(node) unless %i[block numblock].include?(node.type)
        call, *rest = node.children
        node.updated(nil, [yield(call), *rest])
      end

      def rewrite(call, key, &)
        receiver, selector, *args = call.children
        position = index(args)
        return call unless position
        apply(args, position, key, &)
        call.updated(nil, [receiver, selector, *args])
      end

      def index(args)
        args.rindex { |a| a.is_a?(Parser::AST::Node) && %i[kwargs hash].include?(a.type) }
      end

      def apply(args, position, key)
        hash = args[position]
        pairs = hash.children.filter_map { |pair| matches?(pair, key) ? yield(pair) : pair }
        pairs.empty? ? args.delete_at(position) : args[position] = hash.updated(nil, pairs)
      end

      def matches?(pair, key)
        symbol = pair.children.first
        pair.type == :pair && symbol.type == :sym &&
          symbol.children.first.to_s == key
      end
    end
  end
end
