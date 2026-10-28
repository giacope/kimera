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
      INDENT = "  "

      Margin =
        Data.define(:depth, :flat) do
          def deeper = with(depth: depth + 1)

          def newline = flat ? "; " : "\n#{INDENT * depth}"

          def gap = flat ? "" : "\n"
        end

      Mode = Data.define(:open, :pattern)
      OPEN = Mode.new(open: true, pattern: false)

      def initialize(binders, margin, locals = Binders::NONE, mode = OPEN)
        @binders = binders
        @margin = margin
        @locals = locals
        @mode = mode
      end

      def write(node, floor = Level::STATEMENT)
        form = form(node)
        text = slice(node) || form.text
        form.level < floor ? "(#{text})" : text
      end

      def form(node)
        FORMS.fetch(node.type) { raise(ArgumentError, "kimera cannot write a #{node.type}") }.new(node, self)
      end

      def level(node) = form(node).level

      def slice(node) = @binders.slice(node, @locals)

      def lead(node, floor) = write(node, level(node) == Level::KEYWORD ? [floor, Level::KEYWORD].min : floor)

      def head(node) = write(node, level(node) == Level::KEYWORD ? Level::KEYWORD : Level::PRIMARY)

      def deeper = Pen.new(@binders, @margin.deeper, @locals)

      def closed = Pen.new(@binders, @margin, @locals, Mode.new(open: false, pattern: false))

      def opened = Pen.new(@binders, @margin, @locals)

      def patterned = Pen.new(@binders, @margin, @locals, @mode.with(pattern: true))

      def open? = @mode.open

      def pattern? = @mode.pattern

      def with(nodes) = bound(nodes.reduce(Binders::NONE) { |names, node| names | @binders.of(node) })

      def bound(names) = Pen.new(@binders, @margin, (@locals | names).freeze, @mode)

      def scoped(nodes = []) = Pen.new(@binders, @margin, Binders::NONE, @mode.with(pattern: false)).with(nodes)

      def local?(name) = @locals.include?(name)

      def newline = @margin.newline

      def gap = @margin.gap
    end
  end
end
