# frozen_string_literal: true

module Kimera
  class Scribe
    class Selection < Form
      TYPES = %i[case case_match].freeze

      def text
        subject = children.first
        arms = (1...(children.size - 1)).sum("") { |index| part(index) }
        "#{subject ? "case #{part(0, Level::EXPRESSION)}" : "case"}#{arms}#{otherwise}#{closing}"
      end

      def level = Level::KEYWORD

      private

      def otherwise
        fallback = children.last
        return "" unless fallback
        "\n#{margin}else#{lines(fallback.type == :empty_else ? nil : fallback, pens.last)}"
      end
    end

    class Arm < Form
      TYPES = %i[when in_pattern].freeze
      GUARDS = { if_guard: "if", unless_guard: "unless" }.freeze

      def text = "\n#{margin}#{head}#{lines(children.last, pens.last)}"

      private

      def head = type == :when ? "when #{parts(0...(children.size - 1))}" : "in #{part(0)}#{guard}"

      def guard
        clause = children[1]
        clause ? " #{GUARDS.fetch(clause.type)} #{pens[1].write(clause.children.first, Level::EXPRESSION)}" : ""
      end
    end

    class Loop < Form
      TYPES = %i[while until while_post until_post].freeze

      def text
        return "#{part(1, Level::KEYWORD)} #{keyword} #{after(children[1])}" if post?
        modifier? ? Postfix.new(keyword, *children, @pen).text : block
      end

      def level = post? || modifier? ? Level::STATEMENT : Level::KEYWORD

      private

      def keyword = type.to_s.delete_suffix("_post")

      def block = "#{keyword} #{part(0, Level::EXPRESSION)}#{lines(children[1], pens[1])}#{closing}"

      def after(body) = @pen.with([body]).write(children[0], Level::EXPRESSION)

      def post? = type.end_with?("_post")

      def modifier? = children[1] && Postcondition.new(*children, @pen).needed?
    end

    class Iteration < Form
      TYPES = %i[for].freeze

      def text
        "for #{Target.new(
          children.first,
          @pen
        ).text} in #{part(1, Level::EXPRESSION)}#{lines(children[2], pens[2])}#{closing}"
      end

      def level = Level::KEYWORD
    end

    class Jump < Form
      TYPES = %i[return next break].freeze
      WRAPPED = %i[while until].freeze

      def text = children.empty? ? type.to_s : "#{type} #{arguments}"

      def level = Level::EXPRESSION

      private

      def arguments
        only = children.first
        return Condition.new(only, @pen).ternary if children.one? && only.type == :if
        children.each_index.map { |index| argument(index) }.join(", ")
      end

      def argument(index)
        WRAPPED.include?(children.fetch(index).type) ? "(#{part(index)})" : part(index, Level::ASSIGNMENT)
      end
    end

    class Connective < Form
      TYPES = %i[and or].freeze
      FLOWS = %i[return next break].freeze
      SYMBOLS = { and: "&&", or: "||" }.freeze

      def text
        return "#{leading(0, Level::EXPRESSION)} #{type} #{right(Level::ASSIGNMENT)}" if keyword?
        "#{leading(0, level)} #{SYMBOLS.fetch(type)} #{right(level + 1)}"
      end

      def level
        return Level::EXPRESSION if keyword?
        type == :and ? Level::AND : Level::OR
      end

      private

      def keyword? = Shape.new(@node).spelled?(type.to_s) || children.any? { |child| FLOWS.include?(child.type) }

      def right(floor)
        node = children[1]
        bare = FLOWS.include?(node.type) || (keyword? && Shape.new(node).spelled?("not"))
        bare ? part(1) : trailing(1, floor)
      end
    end
  end
end
