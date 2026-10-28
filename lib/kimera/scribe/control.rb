# frozen_string_literal: true

module Kimera
  class Scribe
    class Condition < Form
      TYPES = %i[if_node].freeze

      def text
        return Postfix.new(keyword, @node.predicate, @node.statements, @pen).text if postcondition?
        "#{keyword} #{guard}#{lines(@node.statements, pen_of(@node.statements))}#{alternative}#{closing}"
      end

      def level = postcondition? ? Level::STATEMENT : Level::KEYWORD

      def ternary
        middle, last = sides
        "#{leading(@node.predicate, Level::RANGE)} ? #{branch(middle, Level::RANGE)} : #{branch(last, Level::RANGE)}"
      end

      private

      def keyword = "if"

      def following = @node.subsequent

      def sides = [@node.statements, otherwise]

      def otherwise
        subsequent = following
        subsequent&.type == :else_node ? subsequent.statements : subsequent
      end

      def guard = ended(part(@node.predicate, Level::EXPRESSION))

      def branch(node, floor)
        return "nil" unless node
        pen = pen_of(node).opened
        body = node.type == :statements_node ? node.body : [node]
        return "(#{Sequence.new(node, pen).text})" unless body.one?
        only = body.first
        pen.write(only, Shape.new(only).assignment? ? Level::ASSIGNMENT : floor)
      end

      def alternative
        subsequent = following
        return "" unless subsequent
        pen = pen_of(subsequent)
        return "#{newline}else#{lines(subsequent.statements, pen)}" if subsequent.type == :else_node
        "#{newline}els#{pen.write(subsequent).delete_suffix(closing)}"
      end

      def postcondition?
        body = @node.statements
        !following && body && Postcondition.new(@node.predicate, body, @pen).needed?
      end
    end

    class Unless < Condition
      TYPES = %i[unless_node].freeze

      private

      def keyword = "unless"

      def following = @node.else_clause

      def sides = [otherwise, @node.statements]
    end

    class Postfix
      def initialize(keyword, condition, body, pen)
        @keyword = keyword
        @condition = condition
        @body = body
        @pen = pen
      end

      def text
        "#{Body.new(@body, @pen.closed).text} #{@keyword} #{@pen.with([@body]).write(@condition, Level::EXPRESSION)}"
      end
    end

    class Body
      def initialize(node, pen)
        @node = node
        @pen = pen
      end

      def text
        body = @node.body
        body.one? ? @pen.write(body.first, Level::EXPRESSION) : "(#{Sequence.new(@node, @pen.opened).text})"
      end
    end

    class Postcondition
      SEALED = %i[def_node class_node module_node singleton_class_node].freeze

      def initialize(condition, body, pen)
        @condition = condition
        @body = body
        @pen = pen
      end

      def needed?
        after = @pen.with([@body])
        reads(@condition).any? { |name| after.local?(name) && !@pen.local?(name) }
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
