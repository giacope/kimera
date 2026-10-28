# frozen_string_literal: true

module Kimera
  class Scribe
    class Binders
      OPENING = {
        def_node: %i[receiver], class_node: %i[constant_path superclass], module_node: %i[constant_path],
        singleton_class_node: %i[expression], block_node: [], lambda_node: []
      }.freeze

      def initialize(texts = Texts.new)
        @memo = {}.compare_by_identity
        @texts = texts
      end

      def slice(node, locals, &) = @texts.of(node, locals, &)

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
        fields = OPENING[type]
        fields ? fields.filter_map { |field| node.public_send(field) } : node.compact_child_nodes
      end
    end
  end
end
