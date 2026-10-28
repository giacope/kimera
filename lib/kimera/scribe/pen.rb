# frozen_string_literal: true

module Kimera
  class Scribe
    class Pens
      def initialize(pen, nodes)
        @pen = pen
        @nodes = nodes
      end

      def list = @nodes.each_with_object([@pen]) { |node, pens| pens << pens.last.with([node]) }.first(@nodes.size)

      def index = @nodes.zip(list).each_with_object({}.compare_by_identity) { |(node, pen), map| map[node] = pen }
    end

    class Pen
      class Margin
        def initialize(depth:, flat:)
          @depth = depth
          @flat = flat
        end

        def deeper = Margin.new(depth: depth + 1, flat: flat)

        def flattened = Margin.new(depth: depth, flat: true)

        def newline = flat ? "; " : "\n#{INDENT * depth}"

        def gap = flat ? "" : "\n"

        private

        attr_reader :depth, :flat
      end

      class Mode
        def initialize(open:, pattern:)
          @open = open
          @pattern = pattern
        end

        def open? = @open

        def pattern? = @pattern

        def patterned = Mode.new(open: @open, pattern: true)
      end
      OPEN = Mode.new(open: true, pattern: false)

      def initialize(binders, margin, locals = NO_NAMES, mode = OPEN)
        @binders = binders
        @margin = margin
        @locals = locals
        @mode = mode
      end

      def write(node, floor = STATEMENT)
        form = form(node)
        text = slice(node) || form.text
        form.level < floor ? "(#{text})" : text
      end

      def form(node)
        FORMS.fetch(node.type) { raise(ArgumentError, "kimera cannot write a #{node.type}") }.new(node, self)
      end

      def level(node) = form(node).level

      def slice(node) = @binders.slice(node, @locals)

      def lead(node, floor) = write(node, level(node) == KEYWORD ? [floor, KEYWORD].min : floor)

      def head(node) = write(node, level(node) == KEYWORD ? KEYWORD : PRIMARY)

      def deeper = Pen.new(@binders, @margin.deeper, @locals)

      def closed = Pen.new(@binders, @margin, @locals, Mode.new(open: false, pattern: false))

      def opened = Pen.new(@binders, @margin, @locals)

      def patterned = Pen.new(@binders, @margin, @locals, @mode.patterned)

      def open? = @mode.open?

      def pattern? = @mode.pattern?

      def with(nodes) = bound(nodes.reduce(NO_NAMES) { |names, node| names | @binders.of(node) })

      def bound(names) = Pen.new(@binders, @margin, (@locals | names).freeze, @mode)

      def scoped(nodes = []) = Pen.new(@binders, @margin, NO_NAMES, @mode).with(nodes)

      def local?(name) = @locals.include?(name)

      def newline = @margin.newline

      def gap = @margin.gap
    end
  end
end
