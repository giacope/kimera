# frozen_string_literal: true

require_relative "../parsing/syntax"

module Kimera
  module Rewrite
    class AstWalk
      def initialize(root)
        @root = root
      end

      def rebuild(&) = rebuilt(@root, &)

      def visit(&) = visited(@root, &)

      private

      def rebuilt(node, &)
        changes =
          node.deconstruct_keys(nil).each_with_object({}) do |(field, value), found|
            fresh = renewed(value, &)
            found[field] = fresh unless fresh.equal?(value)
          end
        yield(changes.empty? ? node : node.copy(**changes), node)
      end

      def renewed(value, &)
        case value
        when Kimera::Syntax::Node then rebuilt(value, &)
        when Array then listed(value, &)
        else value
        end
      end

      def listed(values, &)
        fresh = values.map { |value| renewed(value, &) }
        fresh.zip(values).all? { |pair| pair.first.equal?(pair.last) } ? values : fresh
      end

      def visited(node, &)
        yield(node)
        node.compact_child_nodes.each { |child| visited(child, &) }
      end
    end
  end
end
