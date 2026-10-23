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

      def initialize(binders, depth = 0, locals = Binders::NONE, open: true)
        @binders = binders
        @depth = depth
        @locals = locals
        @open = open
      end

      def write(node, floor = Level::STATEMENT)
        form = form(node)
        text = form.text
        form.level < floor ? "(#{text})" : text
      end

      def form(node)
        FORMS.fetch(node.type) { raise(ArgumentError, "kimera cannot write a #{node.type}") }.new(node, self)
      end

      def level(node) = form(node).level

      def lead(node, floor) = write(node, level(node) == Level::KEYWORD ? [floor, Level::KEYWORD].min : floor)

      def head(node) = write(node, level(node) == Level::KEYWORD ? Level::KEYWORD : Level::PRIMARY)

      def deeper = Pen.new(@binders, @depth + 1, @locals)

      def closed = Pen.new(@binders, @depth, @locals, open: false)

      def opened = Pen.new(@binders, @depth, @locals)

      def open? = @open

      def with(nodes) = bound(nodes.reduce(Binders::NONE) { |names, node| names | @binders.of(node) })

      def bound(names) = Pen.new(@binders, @depth, (@locals | names).freeze, open: @open)

      def scoped(nodes = []) = Pen.new(@binders, @depth, Binders::NONE, open: @open).with(nodes)

      def local?(name) = @locals.include?(name)

      def margin = INDENT * @depth
    end
  end
end
