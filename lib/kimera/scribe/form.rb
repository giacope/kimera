# frozen_string_literal: true

module Kimera
  class Scribe
    class Form
      def initialize(node, pen)
        @node = node
        @pen = pen
      end

      def level = Level::PRIMARY

      private

      def children = @node.children

      def type = @node.type

      def pens = @_pens ||= Pens.new(@pen, children).list

      def part(index, floor = Level::STATEMENT) = pens.fetch(index).write(children.fetch(index), floor)

      def leading(index, floor)
        pen = pens.fetch(index).closed
        child = children.fetch(index)
        pen.write(child, pen.level(child) == Level::KEYWORD ? [floor, Level::KEYWORD].min : floor)
      end

      def trailing(index, floor)
        pen = pens.fetch(index)
        child = children.fetch(index)
        bound = pen.level(child) == Level::KEYWORD ? Level::KEYWORD : floor
        bound = Level::ASSIGNMENT if @pen.open? && Shape.new(child).assignment?
        pen.write(child, [floor, bound].min)
      end

      def operand(index, floor)
        child = children.fetch(index)
        Shape.new(child).prefix? && !Shape.new(child).spelled?("not") ? part(index) : trailing(index, floor)
      end

      def receiver_part(index)
        pen = pens.fetch(index).closed
        child = children.fetch(index)
        pen.write(child, pen.level(child) == Level::KEYWORD ? Level::KEYWORD : Level::PRIMARY)
      end

      def parts(indices, floor = Level::ASSIGNMENT)
        indices.map { |index| pens.fetch(index).opened.write(children.fetch(index), floor) }.join(", ")
      end

      def rest(from, floor = Level::ASSIGNMENT) = parts(from...children.size, floor)

      def value_floor(node) = node.type == :rescue ? Level::STATEMENT : Level::ASSIGNMENT

      def enclosed(kind) = "(#{kind.new(@node, @pen).text})"

      def margin = @pen.margin

      def closing(keyword = "end") = "\n#{margin}#{keyword}"

      def lines(node, pen = @pen) = Lines.new(node, pen.deeper).text

      def clauses(node, pen = @pen) = Clauses.new(node, pen).text
    end
  end
end
