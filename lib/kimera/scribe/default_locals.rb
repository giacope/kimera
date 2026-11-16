# frozen_string_literal: true

module Kimera
  class Scribe
    class DefaultLocals
      CLOSURES = %i[block_node lambda_node].freeze

      def initialize(node, scope)
        @node = node
        @scope = scope
      end

      def node
        return @node if renames.empty?
        @node.copy(
          parameters: rewritten(@node.parameters), body: rewritten(@node.body),
          locals: @node.locals.map { |name| renames.fetch(name, name) }
        )
      end

      private

      def names
        bound = @scope.scoped([@node.parameters])
        @node.locals.select { |name| @scope.local?(name) && bound.local?(name) } - parameters(@node.parameters)
      end

      def parameters(node)
        return [] unless node
        return [node.name] if NAMED.include?(node.type)
        node.compact_child_nodes.flat_map { |child| parameters(child) }
      end

      def renames
        @_renames ||= names.to_h { |name| [name, fresh(name)] }
      end

      def fresh(name)
        candidate = :"__kimera_default_#{name}_#{@node.location.start_offset}"
        candidate = :"#{candidate}_" while @scope.local?(candidate) || occupied.include?(candidate)
        candidate
      end

      def occupied
        @_occupied ||= identifiers(@node).to_set
      end

      def identifiers(node)
        [*(node.name if node.respond_to?(:name)), *node.compact_child_nodes.flat_map { |child| identifiers(child) }]
      end

      def rewritten(node, depth = 0)
        return unless node
        fields = rewritten_fields(node, depth)
        name = renames[node.name] if node.respond_to?(:depth) && node.respond_to?(:name) && node.depth == depth
        fields[:name] = name if name
        node.copy(**fields)
      end

      def rewritten_fields(node, depth)
        inner = depth + (CLOSURES.include?(node.type) ? 1 : 0)
        children = children(node).to_h { |child| [child, rewritten(child, inner)] }
        node.deconstruct_keys(nil).transform_values do |value|
          value.is_a?(Array) ? value.map { |item| children.fetch(item, item) } : children.fetch(value, value)
        end
      end

      def children(node)
        CLOSURES.include?(node.type) ? node.compact_child_nodes : Nesting.new(node).outer
      end
    end
  end
end
