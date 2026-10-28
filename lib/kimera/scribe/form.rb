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

      def type = @node.type

      def pens = @_pens ||= Pens.new(@pen, @node.compact_child_nodes).index

      def pen_of(child) = pens.fetch(child, @pen)

      def part(child, floor = Level::STATEMENT) = pen_of(child).write(child, floor)

      def leading(child, floor) = pen_of(child).closed.lead(child, floor)

      def trailing(child, floor)
        pen = pen_of(child)
        bound = pen.level(child) == Level::KEYWORD ? Level::KEYWORD : floor
        bound = Level::ASSIGNMENT if @pen.open? && Shape.new(child).assignment?
        pen.write(child, [floor, bound].min)
      end

      def operand(child, floor)
        shape = Shape.new(child)
        shape.prefix? && !shape.spelled?("not") ? part(child) : trailing(child, floor)
      end

      def receiver_part(child) = pen_of(child).closed.head(child)

      def listed(nodes, floor = Level::ASSIGNMENT)
        nodes.map { |node| pen_of(node).opened.write(node, floor) }.join(", ")
      end

      def trailed(items)
        written = items.reject { |item| item.type == :implicit_rest_node }.map { |item| part(item) }.join(", ")
        items.any? { |item| item.type == :implicit_rest_node } ? "#{written}," : written
      end

      def appended(head, tail, separator) = tail.empty? ? head : "#{head}#{separator}#{tail}"

      def ended(head) = head.end_with?("..") ? "#{head};" : head

      def braced(body, pen, lead = "")
        opening, ending = Clauses.new(body, @pen).structured? ? [" do", "end"] : [" {", "}"]
        "#{opening}#{lead}#{clauses(body, pen)}#{closing(ending)}"
      end

      def present(nodes) = nodes.compact.reject { |node| node.type == :arguments_node && node.arguments.empty? }

      def block_argument = (@node.block if @node.block&.type == :block_argument_node)

      def literal_block = (@node.block if @node.block&.type == :block_node)

      def value_floor(node) = node.type == :rescue_modifier_node ? Level::STATEMENT : Level::ASSIGNMENT

      def enclosed(kind) = "(#{kind.new(@node, @pen).text})"

      def newline = @pen.newline

      def closing(keyword = "end") = "#{newline}#{keyword}"

      def lines(node, pen = @pen) = Lines.new(node, pen.deeper).text

      def clauses(node, pen = @pen) = Clauses.new(node, pen).text
    end
  end
end
