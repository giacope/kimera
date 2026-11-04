# frozen_string_literal: true

module Kimera
  class Scribe
    class Condition < Form
      TYPES = %i[if_node].freeze

      def text
        return modifier(keyword, CLOSED) if postcondition?
        "#{keyword} #{guard}#{lines(@node.statements, scope_of(@node.statements))}#{alternative}#{closing}"
      end

      def level = postcondition? ? STATEMENT : KEYWORD

      def ternary
        middle, last = sides
        "#{leading(@node.predicate, RANGE)} ? #{branch(middle, RANGE)} : #{branch(last, RANGE)}"
      end

      private

      def keyword = "if"

      def following = @node.subsequent

      def sides = [@node.statements, otherwise]

      def otherwise
        subsequent = following
        subsequent&.type == :else_node ? subsequent.statements : subsequent
      end

      def guard = ended(part(@node.predicate, EXPRESSION))

      def branch(node, floor)
        return "nil" unless node
        scope = scope_of(node)
        body = node.type == :statements_node ? node.body : [node]
        return "(#{@pen.form(node, scope, OPEN).text})" unless body.one?
        only = body.first
        @pen.form(only, scope, OPEN).written(Shape.new(only).assignment? ? ASSIGNMENT : floor)
      end

      def alternative
        subsequent = following
        return "" unless subsequent
        scope = scope_of(subsequent)
        return "#{newline}else#{lines(subsequent.statements, scope)}" if subsequent.type == :else_node
        "#{newline}els#{@pen.form(subsequent, scope, @mode).written(STATEMENT).delete_suffix(closing)}"
      end

      def postcondition?
        body = @node.statements
        !following && body && Postcondition.new(@node.predicate, body, @scope).needed?
      end
    end

    class Unless < Condition
      TYPES = %i[unless_node].freeze

      private

      def keyword = "unless"

      def following = @node.else_clause

      def sides = [otherwise, @node.statements]
    end

    class Postcondition
      SEALED = %i[def_node class_node module_node singleton_class_node].freeze

      def initialize(condition, body, scope)
        @condition = condition
        @body = body
        @scope = scope
      end

      def needed?
        after = @scope.with([@body])
        reads(@condition).any? { |name| after.local?(name) && !@scope.local?(name) }
      end

      private

      def reads(node, nesting = 0)
        type = node.type
        return node.depth == nesting ? [node.name] : [] if type == :local_variable_read_node
        return [] if SEALED.include?(type)
        inner = %i[block_node lambda_node].include?(type) ? nesting + 1 : nesting
        node.compact_child_nodes.flat_map { reads(it, inner) }
      end
    end
  end
end
