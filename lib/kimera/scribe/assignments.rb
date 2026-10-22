# frozen_string_literal: true

module Kimera
  class Scribe
    class Target < Form
      def text = SHAPES.fetch(@node.type, Named).new(@node, @pen).text
    end

    class Named < Form
      def text = children.first.to_s
    end

    class Group < Form
      def text = enclosed(Targets)
    end

    class Spread < Form
      def text
        target = children.first
        "*#{Target.new(target, @pen).text if target}"
      end
    end

    class Targets < Form
      def text
        written = children.zip(pens).map { |child, pen| Target.new(child, pen).text }.join(", ")
        children.one? && children.first.type != :splat ? "#{written}," : written
      end
    end

    class Attribute < Form
      def text
        name = children[1].to_s.delete_suffix("=")
        dot = type == :csend ? "&." : "."
        children.first ? "#{receiver_part(0)}#{dot}#{name}" : "self#{dot}#{name}"
      end
    end

    class Assignment < Form
      TYPES = %i[lvasgn ivasgn gvasgn cvasgn casgn indexasgn].freeze

      def text
        value = children.last
        target = @node.updated(nil, children[0...-1])
        "#{Target.new(target, @pen).text} = #{@pen.with([target]).write(value, value_floor(value))}"
      end

      def level = Level::ASSIGNMENT
    end

    class Compound < Form
      TYPES = %i[op_asgn or_asgn and_asgn].freeze
      OPERATORS = { or_asgn: "||", and_asgn: "&&" }.freeze

      def text
        operator = OPERATORS.fetch(type) { children[1].to_s }
        last = children.size - 1
        "#{Target.new(children.first, @pen).text} #{operator}= #{part(last, value_floor(children.last))}"
      end

      def level = Level::ASSIGNMENT
    end

    class Multiple < Form
      TYPES = %i[masgn].freeze

      def text = "#{Targets.new(children.first, @pen).text} = #{part(1, value_floor(children.last))}"

      def level = Level::STATEMENT
    end
  end
end
