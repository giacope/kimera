# frozen_string_literal: true

module Kimera
  class Scribe
    class Scope
      def initialize(binders, locals = NO_NAMES)
        @binders = binders
        @locals = locals
      end

      def with(nodes) = bound(nodes.reduce(NO_NAMES) { |names, node| names | @binders.of(node) })

      def bound(names) = Scope.new(@binders, (@locals | names).freeze)

      def scoped(nodes = []) = Scope.new(@binders).with(nodes)

      def local?(name) = @locals.include?(name)
    end

    class Scopes
      def initialize(scope, nodes)
        @scope = scope
        @nodes = nodes
      end

      def list = @nodes.each_with_object([@scope]) { |node, chain| chain << chain.last.with([node]) }.first(@nodes.size)

      def index = @nodes.zip(list).each_with_object({}.compare_by_identity) { |(node, scope), map| map[node] = scope }
    end
  end
end
