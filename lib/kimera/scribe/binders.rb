# frozen_string_literal: true

module Kimera
  class Scribe
    class Binders
      NAMED = %i[
        local_variable_write_node local_variable_target_node local_variable_operator_write_node
        local_variable_or_write_node local_variable_and_write_node required_parameter_node optional_parameter_node
        rest_parameter_node required_keyword_parameter_node optional_keyword_parameter_node
        keyword_rest_parameter_node block_parameter_node block_local_variable_node
      ].freeze
      OPENING = {
        def_node: %i[receiver], class_node: %i[constant_path superclass], module_node: %i[constant_path],
        singleton_class_node: %i[expression], block_node: [], lambda_node: []
      }.freeze
      NONE = Set.new.freeze

      def initialize(texts = Texts.new)
        @memo = {}.compare_by_identity
        @texts = texts
      end

      def slice(node, locals) = @texts.of(node, locals)

      def of(node)
        return NONE unless node
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
