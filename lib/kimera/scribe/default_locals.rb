# frozen_string_literal: true

require_relative "captured_locals"

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

      def fresh(name, reserved = occupied)
        candidate = :"__kimera_default_#{name}_#{@node.location.start_offset}"
        candidate = :"#{candidate}_" while @scope.local?(candidate) || reserved.include?(candidate)
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
        fields = rebuilt(node, depth)
        name = renames[node.name] if node.respond_to?(:depth) && node.respond_to?(:name) && node.depth == depth
        fields[:name] = name if name
        expanded(node, node.copy(**fields))
      end

      def expanded(original, changed)
        return changed.value if original.type == :implicit_node
        return changed unless original.type == :match_write_node
        temporary = fresh(:"match_#{original.location.start_offset}", occupied | renames.values)
        CapturedLocals.new(original, changed, temporary).node
      end

      def rebuilt(node, depth)
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
