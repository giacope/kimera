# frozen_string_literal: true

module Kimera
  module Rewrite
    class Invocation
      HASHES = %i[keyword_hash_node hash_node].freeze

      def initialize(node)
        @node = node
      end

      def listed
        given = @node.arguments
        arguments = yield(given&.arguments || [])
        @node.copy(arguments: arguments.empty? ? nil : given.copy(arguments: arguments))
      end

      def rewrite(key, &)
        listed do |arguments|
          position = arguments.rindex { |argument| HASHES.include?(argument.type) }
          position ? apply(arguments, position, key, &) : arguments
        end
      end

      private

      def apply(arguments, position, key)
        hash = arguments[position]
        pairs = hash.elements.filter_map { |pair| matches?(pair, key) ? yield(pair) : pair }
        arguments[0...position] + (pairs.empty? ? [] : [hash.copy(elements: pairs)]) + arguments[(position + 1)..]
      end

      def matches?(pair, key)
        symbol = pair.key if pair.type == :assoc_node
        symbol&.type == :symbol_node && symbol.unescaped == key
      end
    end
  end
end
