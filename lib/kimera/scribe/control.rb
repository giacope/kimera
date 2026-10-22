# frozen_string_literal: true

module Kimera
  class Scribe
    class Condition < Form
      TYPES = %i[if].freeze

      def text
        return Postfix.new(children[1] ? "if" : "unless", children[0], body, @pen).text if postcondition?
        children[1].nil? && children[2] ? negative : positive
      end

      def level = postcondition? ? Level::STATEMENT : Level::KEYWORD

      def ternary = "#{leading(0, Level::RANGE)} ? #{middle} : #{children[2] ? trailing(2, Level::RANGE) : "nil"}"

      def chained? = type == :if && children[1] && !postcondition?

      private

      def guard = part(0, Level::EXPRESSION)

      def positive = "if #{guard}#{lines(children[1], pens[1])}#{alternative}#{closing}"

      def negative = "unless #{guard}#{lines(children[2], pens[2])}#{closing}"

      def middle
        branch = children[1]
        return "nil" unless branch
        pens[1].opened.write(branch, Shape.new(branch).assignment? ? Level::ASSIGNMENT : Level::RANGE)
      end

      def alternative
        branch = children[2]
        return "" unless branch
        pen = pens[2]
        nested = Condition.new(branch, pen)
        return "\n#{margin}els#{nested.text.delete_suffix(closing)}" if nested.chained?
        "\n#{margin}else#{lines(branch, pen)}"
      end

      def body = children[1] || children[2]

      def postcondition? = (children[1].nil? ^ children[2].nil?) && Postcondition.new(children[0], body, @pen).needed?
    end

    class Postfix
      def initialize(keyword, condition, body, pen)
        @keyword = keyword
        @condition = condition
        @body = body
        @pen = pen
      end

      def text
        "#{@pen.closed.write(@body, Level::EXPRESSION)} #{@keyword} #{@pen.with([@body]).write(@condition, Level::EXPRESSION)}"
      end
    end

    class Postcondition
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

      def reads(node)
        node.type == :lvar ? node.children : node.children.grep(Parser::AST::Node).flat_map { reads(it) }
      end
    end
  end
end
