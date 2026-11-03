# frozen_string_literal: true

module Kimera
  class Scribe
    class Form
      def initialize(node, pen, scope, mode)
        @node = node
        @pen = pen
        @scope = scope
        @mode = mode
      end

      def level = PRIMARY

      def jump? = false

      def written(floor)
        written = @pen.slice(@node, @scope) { text }
        level < floor ? "(#{written})" : written
      end

      private

      def type = @node.type

      def scopes = @_scopes ||= Scopes.new(@scope, @node.compact_child_nodes).index

      def scope_of(child) = scopes.fetch(child, @scope)

      def form_of(child, mode = @mode) = @pen.form(child, scope_of(child), mode)

      def part(child, floor = STATEMENT) = form_of(child).written(floor)

      def bound(child, names, floor) = @pen.form(child, scope_of(child).bound(names), @mode).written(floor)

      def patterned(child) = form_of(child, @mode.patterned).written(STATEMENT)

      def leading(child, floor)
        form = form_of(child, CLOSED)
        form.written(form.level == KEYWORD ? [floor, KEYWORD].min : floor)
      end

      def trailing(child, floor)
        form = form_of(child)
        bound = form.level == KEYWORD ? KEYWORD : floor
        bound = ASSIGNMENT if @mode.open? && Shape.new(child).assignment?
        form.written([floor, bound].min)
      end

      def operand(child, floor)
        Shape.new(child).prefix? && !Token.new(child).spelled?("not") ? part(child) : trailing(child, floor)
      end

      def receiver_part(child) = leading(child, PRIMARY)

      def listed(nodes, floor = ASSIGNMENT) = nodes.map { |node| form_of(node, OPEN).written(floor) }.join(", ")

      def trailed(items)
        written = items.reject { |item| item.type == :implicit_rest_node }.map { |item| part(item) }.join(", ")
        items.any? { |item| item.type == :implicit_rest_node } ? "#{written}," : written
      end

      def appended(head, tail, separator) = tail.empty? ? head : "#{head}#{separator}#{tail}"

      def ended(head) = head.end_with?("..") ? "#{head};" : head

      def braced(body, scope, lead = "")
        opening, ending = Clauses.new(body, @pen, @scope, @mode).structured? ? [" do", "end"] : [" {", "}"]
        "#{opening}#{lead}#{clauses(body, scope)}#{closing(ending)}"
      end

      def present(nodes) = nodes.compact.reject { |node| node.type == :arguments_node && node.arguments.empty? }

      def block_argument = (@node.block if @node.block&.type == :block_argument_node)

      def literal_block = (@node.block if @node.block&.type == :block_node)

      def attached(block) = Block.new(block, @pen, scope_of(block), @mode).suffix

      def modifier(keyword, mode)
        body = @node.statements
        written = modified(body, mode)
        "#{written} #{keyword} #{@pen.form(@node.predicate, @scope.with([body]), @mode).written(EXPRESSION)}"
      end

      def modified(statements, mode)
        body = statements.body
        return @pen.form(body.first, @scope, mode).written(EXPRESSION) if body.one?
        "(#{@pen.form(statements, @scope, OPEN).text})"
      end

      def value_floor(node) = node.type == :rescue_modifier_node ? STATEMENT : ASSIGNMENT

      def enclosed(kind) = "(#{kind.new(@node, @pen, @scope, @mode).text})"

      def newline = @pen.newline

      def closing(keyword = "end") = "#{newline}#{keyword}"

      def lines(node, scope = @scope) = @pen.lines(node, scope)

      def clauses(node, scope = @scope) = Clauses.new(node, @pen, scope, @mode).text
    end
  end
end
