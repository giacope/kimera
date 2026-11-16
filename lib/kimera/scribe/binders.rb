# frozen_string_literal: true

module Kimera
  class Scribe
    class Nesting
      OPENING = {
        def_node: %i[receiver], class_node: %i[constant_path superclass], module_node: %i[constant_path],
        singleton_class_node: %i[expression], block_node: [], lambda_node: []
      }.freeze

      def initialize(node)
        @node = node
      end

      def outer
        fields = OPENING[@node.type]
        fields ? fields.filter_map { |field| @node.public_send(field) } : @node.compact_child_nodes
      end
    end

    class Binders
      def initialize
        @memo = {}.compare_by_identity
      end

      def of(node)
        return NO_NAMES unless node
        @memo[node] ||= declared(node).freeze
      end

      private

      def declared(node)
        type = node.type
        own = NAMED.include?(type) ? Set.new([node.name].compact) : Set.new
        outer(node, type).reduce(own) { |names, child| names | of(child) }
      end

      def outer(node, type)
        return [node.call] if type == :match_write_node && node.call.receiver&.type != :regular_expression_node
        Nesting.new(node).outer
      end
    end
  end
end
