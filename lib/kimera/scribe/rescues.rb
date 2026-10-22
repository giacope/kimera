# frozen_string_literal: true

module Kimera
  class Scribe
    class Bracketed < Form
      TYPES = %i[kwbegin].freeze

      def text = "begin#{children.one? ? clauses(children.first) : lines(@node.updated(:begin), @pen)}#{closing}"

      def level = Level::KEYWORD
    end

    class Rescued < Form
      TYPES = %i[rescue].freeze

      def text
        return "begin#{clauses(@node)}#{closing}" unless modifier?
        fallback = children[1].children.last || @node.updated(:nil, [])
        "#{leading(0, Level::TERNARY)} rescue #{@pen.with([children.first]).write(fallback, Level::EXPRESSION)}"
      end

      def level = modifier? ? Level::STATEMENT : Level::KEYWORD

      private

      def modifier?
        body, handler, *rest = children
        body && rest == [nil] && handler.children.first(2).none?
      end
    end

    class Ensured < Form
      TYPES = %i[ensure].freeze

      def text = "begin#{clauses(@node)}#{closing}"

      def level = Level::KEYWORD
    end

    class Exceptions < Form
      def text = children.zip(pens).map { |child, pen| exception(child, pen) }.join(", ")

      private

      def exception(child, pen)
        child.type == :if ? Condition.new(child, pen).ternary : pen.write(child, Level::ASSIGNMENT)
      end
    end

    class Exchange < Form
      TYPES = %i[alias undef].freeze

      def text = "#{type} #{children.each_index.map { |index| part(index) }.join(type == :alias ? " " : ", ")}"

      def level = Level::STATEMENT
    end

    class Hook < Form
      TYPES = %i[preexe postexe].freeze

      def text = "#{type == :preexe ? "BEGIN" : "END"} {#{lines(children.first)}#{closing("}")}"

      def level = Level::STATEMENT
    end

    class Capture < Form
      TYPES = %i[match_with_lvasgn].freeze

      def text = "#{leading(0, Level::PRIMARY)} =~ #{trailing(1, Level::EQUALITY + 1)}"

      def level = Level::EQUALITY
    end

    class Bare < Form
      TYPES = %i[match_current_line].freeze

      def text = part(0)
    end
  end
end
