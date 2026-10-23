# frozen_string_literal: true

module Kimera
  class Scribe
    # Where a node is written back into its source: the locals Ruby has bound
    # there (earlier writes and parameters of its scope, and of every block
    # around it), the text of every subtree a rewrite left alone, kept as it
    # was written, and the indentation of its line. Statements may be joined
    # on one line.
    class Place
      SCOPES = %i[program_node def_node class_node module_node singleton_class_node].freeze

      attr_reader :locals, :slices, :depth, :joint

      def self.top = new(Binders::NONE, {}.compare_by_identity, 0)

      def self.of(root, node)
        indent = node.location.start_line_slice[/\A */].size
        new(Seen.new(node).locals(root), Kept.new(node, root).slices, indent / Pen::INDENT.size)
      end

      def initialize(locals, slices, depth, joint = nil)
        @locals = locals
        @slices = slices
        @depth = depth
        @joint = joint
      end

      def after(node) = Place.new(@locals | Binders.new.of(node), @slices, @depth, @joint)

      def joined = Place.new(@locals, @slices, @depth, "; ")

      # The locals bound where a node stands.
      class Seen
        def initialize(node)
          @node = node
        end

        def locals(scope, names = Binders::NONE)
          return names if scope.equal?(@node)
          children = scope.compact_child_nodes
          earlier = children.select { |child| before?(child) }
          seen = earlier.reduce(opened(scope, names)) { |all, child| all | seen(child) }
          inner = children.find { |child| around?(child) }
          inner ? locals(inner, seen) : seen
        end

        private

        def opened(scope, names)
          kept = SCOPES.include?(scope.type) ? Binders::NONE : names
          Binders::NAMED.include?(scope.type) ? kept | [scope.name].compact : kept
        end

        def seen(node) = (@_binders ||= Binders.new).of(node)

        def before?(child) = child.location.end_offset <= @node.location.start_offset

        def around?(child) = span(child).cover?(span(@node))

        def span(node) = node.location.start_offset..node.location.end_offset
      end
    end
  end
end

require_relative "kept"
