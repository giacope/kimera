# frozen_string_literal: true

module Kimera
  class Scribe
    class Place
      SCOPES = %i[program_node def_node class_node module_node singleton_class_node].freeze

      def self.top = new(NO_NAMES, {}.compare_by_identity, Margin.new(depth: 0, flat: false))

      def self.of(root, node, ends = Float::INFINITY)
        indent = node.location.start_line_slice[/\A */].size
        margin = Margin.new(depth: indent / INDENT.size, flat: false)
        new(Seen.new(node).locals(root), Kept.new(node, root, ends).slices, margin)
      end

      def initialize(locals, slices, margin, binders = Binders.new)
        @locals = locals
        @slices = slices
        @margin = margin
        @binders = binders
      end

      def after(node) = Place.new(@locals | @binders.of(node), @slices, @margin, @binders)

      def joined = Place.new(@locals, @slices, @margin.flattened, @binders)

      def unbroken = Place.new(@locals, @slices.reject { |_, text| text.include?("\n") }, @margin.flattened, @binders)

      def written(node) = Lines.new(node, pen, scope, @margin).text.delete_prefix(@margin.newline)

      private

      def pen = Pen.new(Texts.new(@slices), @margin)

      def scope = Scope.new(@binders, @locals)

      class Seen
        def initialize(node, binders = Binders.new)
          @node = node
          @binders = binders
        end

        def locals(scope, names = NO_NAMES)
          return names if scope.equal?(@node)
          children = scope.compact_child_nodes
          earlier = children.select { |child| before?(child) }
          seen = earlier.reduce(opened(scope, names)) { |all, child| all | seen(child) }
          inner = children.find { |child| around?(child) }
          inner ? locals(inner, seen) : seen
        end

        private

        def opened(scope, names)
          kept = SCOPES.include?(scope.type) ? NO_NAMES : names
          NAMED.include?(scope.type) ? kept | [scope.name].compact : kept
        end

        def seen(node) = @binders.of(node)

        def before?(child) = child.location.end_offset <= @node.location.start_offset

        def around?(child) = span(child).cover?(span(@node))

        def span(node) = node.location.start_offset..node.location.end_offset
      end
    end
  end
end

require_relative "kept"
