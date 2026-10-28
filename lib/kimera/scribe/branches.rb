# frozen_string_literal: true

module Kimera
  class Scribe
    class Selection < Form
      TYPES = %i[case_node case_match_node].freeze

      def text
        subject = @node.predicate
        arms = @node.conditions.sum("") { |arm| part(arm) }
        "#{subject ? "case #{part(subject, Level::EXPRESSION)}" : "case"}#{arms}#{otherwise}#{closing}"
      end

      def level = Level::KEYWORD

      private

      def otherwise
        fallback = @node.else_clause
        fallback ? "#{newline}else#{lines(fallback.statements, pen_of(fallback))}" : ""
      end
    end

    class Arm < Form
      TYPES = %i[when_node in_node].freeze
      GUARDS = { if_node: "if", unless_node: "unless" }.freeze

      def text = "#{newline}#{head}#{lines(@node.statements, pen_of(@node.statements))}"

      private

      def head = ended(type == :when_node ? "when #{listed(@node.conditions)}" : "in #{pattern}")

      def pattern
        tested = @node.pattern
        word = GUARDS[tested.type]
        return part(tested) unless word
        inner = tested.statements.body.first
        pen = pen_of(tested)
        "#{pen.write(inner)} #{word} #{pen.with([inner]).write(tested.predicate, Level::EXPRESSION)}"
      end
    end

    class Loop < Form
      TYPES = %i[while_node until_node].freeze

      def text
        return "#{Body.new(@node.statements, @pen).text} #{keyword} #{after}" if @node.begin_modifier?
        return Postfix.new(keyword, @node.predicate, @node.statements, @pen).text if modifier?
        "#{keyword} #{guard}#{body}#{closing}"
      end

      def level = @node.begin_modifier? || modifier? ? Level::STATEMENT : Level::KEYWORD

      private

      def keyword = type == :while_node ? "while" : "until"

      def guard = ended(part(@node.predicate, Level::EXPRESSION))

      def body = lines(@node.statements, pen_of(@node.statements))

      def after = @pen.with([@node.statements]).write(@node.predicate, Level::EXPRESSION)

      def modifier? = @node.statements && Postcondition.new(@node.predicate, @node.statements, @pen).needed?
    end

    class Iteration < Form
      TYPES = %i[for_node].freeze

      def text
        body = @node.statements
        collection = ended(part(@node.collection, Level::EXPRESSION))
        "for #{part(@node.index)} in #{collection}#{lines(body, pen_of(body))}#{closing}"
      end

      def level = Level::KEYWORD
    end

    class Jump < Form
      TYPES = %i[return_node next_node break_node].freeze
      WORDS = { return_node: "return", next_node: "next", break_node: "break" }.freeze
      WRAPPED = %i[while_node until_node].freeze

      def text
        appended(WORDS.fetch(type), arguments(@node.arguments&.arguments || []), " ")
      end

      def level = Level::EXPRESSION

      private

      def arguments(values)
        pen = pen_of(@node.arguments)
        only = values.first
        return pen.form(only).ternary if values.one? && %i[if_node unless_node].include?(only.type)
        values.map do |value|
          WRAPPED.include?(value.type) ? "(#{pen.write(value)})" : pen.write(value, Level::ASSIGNMENT)
        end.join(", ")
      end
    end

    class Connective < Form
      TYPES = %i[and_node or_node].freeze
      FLOWS = %i[return_node next_node break_node].freeze
      SYMBOLS = { and_node: "&&", or_node: "||" }.freeze
      WORDS = { and_node: "and", or_node: "or" }.freeze

      def text
        return "#{leading(@node.left, Level::EXPRESSION)} #{WORDS.fetch(type)} #{right(Level::ASSIGNMENT)}" if keyword?
        "#{leading(@node.left, level)} #{SYMBOLS.fetch(type)} #{right(level + 1)}"
      end

      def level
        return Level::EXPRESSION if keyword?
        type == :and_node ? Level::AND : Level::OR
      end

      private

      def keyword?
        Shape.new(@node).spelled?(WORDS.fetch(type)) || [@node.left, @node.right].any? { |child| carrying?(child) }
      end

      def carrying?(child) = FLOWS.include?(child.type) && child.arguments

      def right(floor)
        node = @node.right
        bare = FLOWS.include?(node.type) || (keyword? && Shape.new(node).spelled?("not"))
        bare ? part(node) : trailing(node, floor)
      end
    end
  end
end
