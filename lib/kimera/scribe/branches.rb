# frozen_string_literal: true

module Kimera
  class Scribe
    class Selection < Form
      TYPES = %i[case_node case_match_node].freeze

      def text
        subject = @node.predicate
        arms = @node.conditions.sum("") { |arm| part(arm) }
        "#{subject ? "case #{part(subject, EXPRESSION)}" : "case"}#{arms}#{otherwise}#{closing}"
      end

      def level = KEYWORD

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
        return patterned(tested) unless word
        inner = tested.statements.body.first
        pen = pen_of(tested)
        "#{pen.patterned.write(inner)} #{word} #{pen.with([inner]).write(tested.predicate, EXPRESSION)}"
      end
    end

    class Loop < Form
      TYPES = %i[while_node until_node].freeze

      def text
        return "#{Body.new(@node.statements, @pen).text} #{keyword} #{after}" if @node.begin_modifier?
        return Postfix.new(keyword, @node.predicate, @node.statements, @pen).text if modifier?
        "#{keyword} #{guard}#{body}#{closing}"
      end

      def level = @node.begin_modifier? || modifier? ? STATEMENT : KEYWORD

      private

      def keyword = type == :while_node ? "while" : "until"

      def guard = ended(part(@node.predicate, EXPRESSION))

      def body = lines(@node.statements, pen_of(@node.statements))

      def after = @pen.with([@node.statements]).write(@node.predicate, EXPRESSION)

      def modifier? = @node.statements && Postcondition.new(@node.predicate, @node.statements, @pen).needed?
    end

    class Iteration < Form
      TYPES = %i[for_node].freeze

      def text
        body = @node.statements
        collection = ended(part(@node.collection, EXPRESSION))
        "for #{part(@node.index)} in #{collection}#{lines(body, pen_of(body))}#{closing}"
      end

      def level = KEYWORD
    end

    class Jump < Form
      WORDS = { return_node: "return", next_node: "next", break_node: "break" }.freeze
      TYPES = WORDS.keys.freeze
      WRAPPED = %i[while_node until_node].freeze

      def text
        appended(WORDS.fetch(type), arguments(@node.arguments&.arguments || []), " ")
      end

      def level = EXPRESSION

      def jump? = true

      private

      def arguments(values)
        pen = pen_of(@node.arguments)
        only = values.first
        return pen.form(only).ternary if values.one? && %i[if_node unless_node].include?(only.type)
        values.map do |value|
          WRAPPED.include?(value.type) ? "(#{pen.write(value)})" : pen.write(value, ASSIGNMENT)
        end.join(", ")
      end
    end

    class Connective < Form
      TYPES = %i[and_node or_node].freeze
      FLOWS = %i[return_node next_node break_node].freeze
      SYMBOLS = { and_node: "&&", or_node: "||" }.freeze
      WORDS = { and_node: "and", or_node: "or" }.freeze

      def text
        return "#{leading(@node.left, EXPRESSION)} #{WORDS.fetch(type)} #{right(ASSIGNMENT)}" if keyword?
        "#{leading(@node.left, level)} #{SYMBOLS.fetch(type)} #{right(level + 1)}"
      end

      def level
        return EXPRESSION if keyword?
        type == :and_node ? AND : OR
      end

      private

      def keyword?
        Token.new(@node).spelled?(WORDS.fetch(type)) || [@node.left, @node.right].any? { |child| carrying?(child) }
      end

      def carrying?(child) = FLOWS.include?(child.type) && child.arguments

      def right(floor)
        node = @node.right
        bare = FLOWS.include?(node.type) || (keyword? && Token.new(node).spelled?("not"))
        bare ? part(node) : trailing(node, floor)
      end
    end
  end
end
